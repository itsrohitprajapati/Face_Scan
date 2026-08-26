"""OpenRouter tool-calling orchestration for teacher attendance questions."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import httpx
from app.config import settings
from app.services.attendance_query import query_attendance
from sqlalchemy.orm import Session

ATTENDANCE_TOOL: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": "search_attendance",
        "description": "Search completed attendance records owned by the authenticated teacher. Always call this tool immediately. Null class means all owned classes, null student means all students, null status means all statuses, and null dates mean all completed sessions. Use ISO dates and never invent IDs.",
        "parameters": {
            "type": "object",
            "properties": {
                "start_date": {"type": ["string", "null"], "description": "Inclusive YYYY-MM-DD date."},
                "end_date": {"type": ["string", "null"], "description": "Inclusive YYYY-MM-DD date."},
                "status": {"type": ["string", "null"], "enum": ["present", "late", "absent", None]},
                "student_name": {"type": ["string", "null"]},
                "class_id": {"type": ["string", "null"], "description": "Only use a class ID supplied in the context."},
            },
            "required": ["start_date", "end_date", "status", "student_name", "class_id"],
            "additionalProperties": False,
        },
    },
}


def _tool_query(arguments: dict[str, Any], teacher_id: UUID, db: Session, available_classes: list[dict[str, str]]) -> dict[str, Any]:
    class_id = UUID(arguments["class_id"]) if arguments.get("class_id") else None
    if class_id is None and len(available_classes) == 1:
        class_id = UUID(available_classes[0]["id"])
    if class_id and class_id not in {UUID(item["id"]) for item in available_classes}:
        raise ValueError("That class is not owned by the authenticated teacher.")
    parts = []
    if arguments.get("start_date") and arguments.get("end_date"):
        parts.append(f"from {arguments['start_date']} to {arguments['end_date']}")
    elif arguments.get("start_date"):
        parts.append(f"on {arguments['start_date']}")
    if arguments.get("status"):
        parts.append(arguments["status"])
    if arguments.get("student_name"):
        parts.append(arguments["student_name"])
    query = "attendance " + " ".join(parts)
    return query_attendance(query, teacher_id, db, class_id)


async def answer_attendance_question(
    question: str,
    teacher_id: UUID,
    db: Session,
    available_classes: list[dict[str, str]],
) -> dict[str, Any]:
    if not settings.openrouter_api_key:
        raise RuntimeError("Natural-language attendance is not configured. Set OPENROUTER_API_KEY on the API server.")

    class_context = json.dumps(available_classes)
    messages: list[dict[str, Any]] = [
        {
            "role": "system",
            "content": (
                "You are a classroom attendance assistant that always returns an answer, never a clarification question. "
                "You MUST call search_attendance for every user request. Resolve relative dates using today's date. "
                "If no class is specified, search all owned classes by passing class_id null. If no student is specified, "
                "search all students. If no status is specified, search all statuses. If no date is specified, search all "
                "completed sessions. Treat requests for today and yesterday as one inclusive range from yesterday to today. "
                "Never ask the teacher to choose a class or student and never expose internal class IDs in your answer. "
                "After the tool returns, answer directly and concisely from its data, including zero-result cases. "
                "Do not claim data that is not in the tool result. Today is " + datetime.now(UTC).date().isoformat() + ". "
                "The authenticated teacher's available classes are: " + class_context
            ),
        },
        {"role": "user", "content": question},
    ]
    headers = {
        "Authorization": f"Bearer {settings.openrouter_api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "http://localhost:5173",
        "X-Title": "Smart Classroom Attendance",
    }
    payload = {
        "model": settings.openrouter_model,
        "messages": messages,
        "tools": [ATTENDANCE_TOOL],
        "tool_choice": {"type": "function", "function": {"name": "search_attendance"}},
        "temperature": 0,
    }
    async with httpx.AsyncClient(base_url=settings.openrouter_base_url, timeout=30) as client:
        response = await client.post("/chat/completions", headers=headers, json=payload)
    response.raise_for_status()
    assistant = response.json()["choices"][0]["message"]
    tool_calls = assistant.get("tool_calls", [])
    if not tool_calls:
        data = query_attendance(question, teacher_id, db)
        return {"answer": "Here are the matching attendance records.", "data": data}

    tool_call = tool_calls[0]
    if tool_call["function"]["name"] != "search_attendance":
        raise RuntimeError("The attendance assistant returned an unsupported tool.")
    arguments = json.loads(tool_call["function"]["arguments"])
    data = _tool_query(arguments, teacher_id, db, available_classes)
    messages.extend([assistant, {"role": "tool", "tool_call_id": tool_call["id"], "content": json.dumps(data, default=str)}])
    follow_up = {
        "model": settings.openrouter_model,
        "messages": messages,
        "temperature": 0,
    }
    async with httpx.AsyncClient(base_url=settings.openrouter_base_url, timeout=30) as client:
        final_response = await client.post("/chat/completions", headers=headers, json=follow_up)
    final_response.raise_for_status()
    answer = final_response.json()["choices"][0]["message"].get("content") or "No attendance summary was generated."
    return {"answer": answer, "data": data}
