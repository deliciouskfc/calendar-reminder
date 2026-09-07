#!/usr/bin/env python3
"""课表提醒脚本 - 提前 30 分钟推送通知到微信"""
import json
import os
import sys
import urllib.request
import urllib.parse
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Asia/Shanghai")

def load_schedule():
    with open("schedule.json", encoding="utf-8") as f:
        return json.load(f)

def is_holiday(date_str, cal):
    for h in cal.get("holidays", []):
        if h["start"] <= date_str <= h["end"]:
            return h["name"]
    return None

def is_exam_period(date_str, cal):
    for p in cal.get("exam_periods", []):
        if p["start"] <= date_str <= p["end"]:
            return True
    return False

def get_school_day(date_str, cal):
    """检查是否应该上课，返回补课的 weekday 或 None"""
    # 先检查是不是补课日
    makeups = [
        {"date": "2026-09-20", "weekday": 5},  # 补周五
    ]
    for m in makeups:
        if m["date"] == date_str:
            return m["weekday"], "补课日"

    if is_holiday(date_str, cal):
        return None, "假期"
    if is_exam_period(date_str, cal):
        return None, "考试期"

    # 检查是否在学期内
    for sem in cal.get("semesters", []):
        if sem["start"] <= date_str <= sem["end"]:
            return None, "学期内"
    return None, "非学期"

def find_upcoming():
    sched = load_schedule()
    now = datetime.now(TZ)
    target = now + timedelta(minutes=30)
    notify_before = sched.get("notify", {}).get("before_minutes", 30)

    date_str = now.strftime("%Y-%m-%d")
    weekday = now.isoweekday()  # 1=周一..7=周日

    cal = sched.get("school_calendar", {})
    makeup_wd, reason = get_school_day(date_str, cal)

    upcoming = []

    # 正常上课日
    if makeup_wd is None and reason in ("学期内", "补课日"):
        effective_wd = makeup_wd if makeup_wd else weekday
        for course in sched["courses"]:
            if course["weekday"] != effective_wd:
                continue
            t = datetime.strptime(course["start"], "%H:%M").time()
            course_dt = datetime.combine(now.date(), t, TZ)
            diff = (course_dt - now).total_seconds() / 60
            if 0 < diff <= notify_before:
                upcoming.append((course, reason))

    # 补课日额外检查补的 weekday
    if makeup_wd and reason == "补课日":
        for course in sched["courses"]:
            if course["weekday"] != makeup_wd:
                continue
            t = datetime.strptime(course["start"], "%H:%M").time()
            course_dt = datetime.combine(now.date(), t, TZ)
            diff = (course_dt - now).total_seconds() / 60
            if 0 < diff <= notify_before:
                upcoming.append((course, f"补课日（补周{['日','一','二','三','四','五','六'][makeup_wd]}）"))

    # 特殊日期（考试等）
    for sp in sched.get("special_dates", []):
        if sp["date"] == date_str:
            t = datetime.strptime("00:00", "%H:%M").time()
            # 考试默认在上午，这里简化处理
            sp_dt = datetime.combine(now.date(), datetime.strptime("09:00", "%H:%M").time(), TZ)
            diff = (sp_dt - now).total_seconds() / 60
            if 0 < diff <= notify_before + 120:  # 考试提前2小时也提醒
                upcoming.append(({"name": sp["name"], "start": "09:00", "end": "--", "location": "考场", "type": sp.get("type", "special")}, sp.get("name", "")))

    return upcoming, now

def push(title, desp):
    key = os.environ.get("SERVERCHAN_KEY", "")
    if not key:
        print("ERROR: SERVERCHAN_KEY not set")
        return False
    url = f"https://sctapi.ftqq.com/{key}.send"
    data = urllib.parse.urlencode({"title": title, "desp": desp}).encode()
    req = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode())
            if result.get("code") == 0:
                print(f"PUSH OK: {title}")
                return True
            else:
                print(f"PUSH FAIL: {result}")
                return False
    except Exception as e:
        print(f"PUSH ERROR: {e}")
        return False

def main():
    upcoming, now = find_upcoming()
    print(f"[{now.strftime('%Y-%m-%d %H:%M')}] 检查完成，发现 {len(upcoming)} 个即将开始的事项")

    if not upcoming:
        print("无即将开始的课")
        return

    for course, reason in upcoming:
        title = f"📚 {course['name']} 即将开始"
        desp = f"""**{course['name']}**
⏰ 时间：{course['start']} - {course['end']}
📍 地点：{course['location']}
🏷️ 类型：{course.get('type', 'Lecture')}
📅 日期：{now.strftime('%Y-%m-%d')}（{reason}）

请准时参加！"""
        push(title, desp)

if __name__ == "__main__":
    main()
