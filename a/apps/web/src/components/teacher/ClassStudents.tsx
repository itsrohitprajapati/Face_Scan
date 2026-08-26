import { useEffect, useState } from 'react'
import { BarChart3, CalendarDays, CheckCircle2, Clock3, GraduationCap, Mail, User as UserIcon } from 'lucide-react'
import { api } from '../../api'
import type { AttendanceSummary, ClassStudent, Classroom } from '../../types'
import { Empty, Metric, Notice, Panel, StatusBadge } from '../ui/primitives'

export function ClassStudents({ classroom, studentId, onSelectStudent }: { classroom: Classroom; studentId: string | null; onSelectStudent: (studentId: string | null) => void }) {
  const [students, setStudents] = useState<ClassStudent[]>([])
  const [attendance, setAttendance] = useState<AttendanceSummary | null>(null)
  const [error, setError] = useState('')
  const [loadingAttendance, setLoadingAttendance] = useState(false)

  useEffect(() => { setError(''); api.listClassStudents(classroom.id).then(setStudents).catch((e) => setError(e.message)) }, [classroom.id])

  useEffect(() => {
    if (!studentId) { setAttendance(null); return }
    setLoadingAttendance(true)
    api.studentAttendanceInClass(classroom.id, studentId).then(setAttendance).catch((e) => setError(e.message)).finally(() => setLoadingAttendance(false))
  }, [classroom.id, studentId])

  const selected = students.find((student) => student.id === studentId) ?? null

  return (
    <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
      <div className="rounded-xl border border-[var(--line)] bg-white">
        <div className="flex items-center justify-between border-b border-[var(--line)] p-5">
          <h2 className="font-semibold">Enrolled students</h2>
          <span className="tabular text-xs text-[var(--muted)]">{students.length}</span>
        </div>
        {error && <div className="p-4"><Notice tone="error">{error}</Notice></div>}
        {students.length === 0 ? (
          <div className="p-5"><Empty text="No students have joined this class yet." /></div>
        ) : (
          <div className="max-h-[560px] overflow-y-auto">
            {students.map((student) => (
              <button
                key={student.id}
                onClick={() => onSelectStudent(student.id)}
                className={`flex w-full items-center gap-3 border-b border-[var(--line)] p-4 text-left transition last:border-0 ${studentId === student.id ? 'bg-[var(--green-soft)]' : 'hover:bg-[#f5f7f4]'}`}
              >
                <span className="grid size-9 shrink-0 place-items-center rounded-full bg-[var(--green-soft)] text-[var(--green)]"><UserIcon size={16} /></span>
                <div className="min-w-0">
                  <p className="truncate text-sm font-bold">{student.full_name}</p>
                  <p className="tabular mt-0.5 truncate text-xs text-[var(--muted)]">Roll {student.roll_number}</p>
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      {!selected ? (
        <div className="grid min-h-72 place-items-center rounded-xl border border-dashed border-[var(--line)] bg-white text-sm text-[var(--muted)]">Select a student to view their attendance.</div>
      ) : (
        <div className="space-y-6">
          <Panel title={selected.full_name} action={<button onClick={() => onSelectStudent(null)} className="text-xs font-bold text-[var(--muted)] hover:text-[var(--ink)]">Close</button>}>
            <div className="flex flex-wrap items-center gap-4 text-sm text-[var(--muted)]">
              <span className="tabular font-bold text-[var(--ink)]">Roll {selected.roll_number}</span>
              <span className="flex items-center gap-1.5"><Mail size={13} /> {selected.email}</span>
              <span className="flex items-center gap-1.5"><GraduationCap size={13} /> Joined {new Date(selected.joined_at).toLocaleDateString()}</span>
            </div>
          </Panel>

          {loadingAttendance ? (
            <Empty text="Loading attendance…" />
          ) : attendance && (
            <>
              <div className="grid gap-3 sm:grid-cols-4">
                <Metric label="Attendance" value={`${attendance.attendance_percentage}%`} icon={<BarChart3 size={17} />} />
                <Metric label="Attended" value={String(attendance.attended_sessions)} icon={<CheckCircle2 size={17} />} />
                <Metric label="Late" value={String(attendance.late_sessions)} icon={<Clock3 size={17} />} />
                <Metric label="Sessions" value={String(attendance.total_sessions)} icon={<CalendarDays size={17} />} />
              </div>
              <div className="overflow-x-auto rounded-xl border border-[var(--line)] bg-white">
                {attendance.history.length === 0 ? (
                  <Empty text="No completed sessions yet for this student." />
                ) : (
                  <table className="w-full min-w-[560px] text-left">
                    <thead className="bg-[#f7f8f6] text-xs uppercase tracking-wide text-[var(--muted)]">
                      <tr>
                        <th className="px-5 py-3 font-bold">Session</th>
                        <th className="px-5 py-3 font-bold">Date</th>
                        <th className="px-5 py-3 font-bold">Coverage</th>
                        <th className="px-5 py-3 font-bold">Automated</th>
                        <th className="px-5 py-3 font-bold">Effective</th>
                      </tr>
                    </thead>
                    <tbody>
                      {attendance.history.map((entry) => (
                        <tr key={entry.session_id} className="border-t border-[var(--line)]">
                          <td className="px-5 py-4 text-sm font-bold">{entry.session_title}</td>
                          <td className="px-5 py-4 text-sm text-[var(--muted)]">{new Date(entry.session_started_at).toLocaleDateString()}</td>
                          <td className="tabular px-5 py-4 text-sm text-[var(--muted)]">{entry.observed_windows}/{entry.eligible_windows} min <span className="font-bold text-[var(--ink)]">({entry.presence_percentage}%)</span></td>
                          <td className="px-5 py-4"><StatusBadge status={entry.automated_status} /></td>
                          <td className="px-5 py-4"><StatusBadge status={entry.effective_status} /></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  )
}
