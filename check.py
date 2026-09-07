#!/usr/bin/env python3
"""
CUHK 课表课前提醒脚本
- 读取 schedule.json
- 检查 30 分钟内是否有课
- 通过 Server酱 (sct.ftqq.com) 推送到微信
- 使用 GitHub Actions 定时运行，推送记录存在 GitHub Actions cache 里防止重复
"""

import json
import os
import sys
import time
import hashlib
import urllib.request
import urllib.parse
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo  # Python 3.9+

TZ = ZoneInfo("Asia/Shanghai")
REMIND_BEFORE = 30  # 提前多少分钟提醒

def load_schedule(path="schedule.json"):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def dk(d):
    return d.strftime("%Y-%m-%d")

def get_date_info(d, cfg):
    key = dk(d)
    info = {"holiday": None, "exam": False, "independent": False, "makeup": None, "semester": None}

    for s in cfg.get("school_calendar", {}).get("semesters", []):
        if s["start"] <= key <= s["end"]:
            info["semester"] = s["name"]
            if s.get("type") == "independent":
                info["independent"] = True
            break

    for h in cfg.get("school_calendar", {}).get("holidays", []):
        if h["start"] <= key <= h["end"]:
            info["holiday"] = h["name"]
            break

    for ep in cfg.get("school_calendar", {}).get("exam_periods", []):
        if ep["start"] <= key <= ep["end"]:
            info["exam"] = True
            break

    return info

def find_today_courses(now, cfg):
    """返回今天要上的课程列表"""
    info = get_date_info(now, cfg)

    # 假期/考试期/独立探索期 → 不上课
    if info["holiday"] or info["exam"] or info["independent"]:
        return []

    courses = cfg.get("courses", [])
    js_wk = now.isoweekday()  # 1=周一..7=周日, 和 schedule.json 一致
    return [c for c in courses if c["weekday"] == js_wk]

def find_upcoming_courses(now, cfg, within_minutes=REMIND_BEFORE):
    """返回 within_minutes 分钟内即将开始的课程"""
    today_courses = find_today_courses(now, cfg)
    upcoming = []

    for c in today_courses:
        h, m = map(int, c["start"].split(":"))
        course_start = now.replace(hour=h, minute=m, second=0, microsecond=0)
        diff_min = (course_start - now).total_seconds() / 60

        # 在 [-1, within_minutes] 分钟内 → 提醒（-1 容差）
        if -1 <= diff_min <= within_minutes:
            upcoming.append({
                "course": c,
                "start_dt": course_start,
                "diff_min": diff_min,
            })

    return upcoming

def send_serverchan(sendkey, title, desp):
    """通过 Server酱 (sct.ftqq.com) 推送到微信"""
    if not sendkey:
        print("[WARN] SERVERCHAN_KEY 未设置，跳过推送")
        return False

    url = f"https://sctapi.ftqq.com/{sendkey}.send"
    data = urllib.parse.urlencode({"title": title, "desp": desp}).encode("utf-8")

    try:
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            if body.get("code") == 0:
                print(f"[OK] 推送成功: {title}")
                return True
            else:
                print(f"[ERROR] 推送失败: {body}")
                return False
    except Exception as e:
        print(f"[ERROR] 推送异常: {e}")
        return False

def make_notice_id(course, start_dt):
    """生成唯一 ID，用于去重"""
    raw = f"{course['name']}|{dk(start_dt)}|{course['start']}"
    return hashlib.md5(raw.encode()).hexdigest()

def main():
    schedule_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schedule.json")
    cfg = load_schedule(schedule_path)

    now = datetime.now(TZ).replace(tzinfo=None)  # 转到本地时间去掉 tz 方便比较
    sendkey = os.environ.get("SERVERCHAN_KEY", "")

    print(f"[{now.strftime('%Y-%m-%d %H:%M:%S')}] 检查课表...")

    upcoming = find_upcoming_courses(now, cfg, cfg.get("notify", {}).get("before_minutes", REMIND_BEFORE))
    print(f"  30分钟内有 {len(upcoming)} 门课")

    if not upcoming:
        print("[DONE] 无即将开始的课，跳过推送")
        return

    # 从缓存读取已推送过的 ID
    cache_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".notified_cache.json")
    notified = set()
    if os.path.exists(cache_path):
        try:
            with open(cache_path, "r") as f:
                notified = set(json.load(f))
        except Exception:
            pass

    pushed_new = []
    for item in upcoming:
        c = item["course"]
        nid = make_notice_id(c, item["start_dt"])
        if nid in notified:
            print(f"  [SKIP] 已推送过: {c['name']}")
            continue

        diff_str = f"还有 {int(item['diff_min'])} 分钟" if item["diff_min"] >= 0 else "正在上课中"
        title = f"📘 {c['name']} {diff_str}"
        desp = (
            f"**课程**: {c['name']}\n\n"
            f"**时间**: {c['start']} - {c['end']}\n\n"
            f"**地点**: {c.get('location', '未填')}\n\n"
            f"**类型**: {c.get('type', 'Lecture')}\n\n"
            f"**日期**: {dk(item['start_dt'])}"
        )

        ok = send_serverchan(sendkey, title, desp)
        if ok:
            notified.add(nid)
            pushed_new.append(c["name"])

    # 写回缓存（最多保留最近 100 条）
    notified = list(notified)[-100:]
    with open(cache_path, "w") as f:
        json.dump(notified, f)

    print(f"[DONE] 本次新推送: {pushed_new if pushed_new else '无'}")

if __name__ == "__main__":
    main()
