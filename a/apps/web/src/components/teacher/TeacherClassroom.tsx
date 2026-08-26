import { useEffect, useState } from 'react'
import type React from 'react'
import { Clipboard, RefreshCw, Trash2, Users, Video } from 'lucide-react'
import { api } from '../../api'
import type { AttendanceRecord, AttendanceSession, Classroom, CameraSource, SessionInsights, Sighting } from '../../types'
import { TeacherCameraPreview } from './TeacherCameraPreview'
import { InsightsPanel } from './InsightsPanel'
import { AttendancePanel } from './AttendancePanel'
import { ClassStudents } from './ClassStudents'
import { DeleteClassModal } from './DeleteClassModal'
import { Empty, Field, Metric, Notice, Panel } from '../ui/primitives'
import { readQueryParams, writeQueryParams } from '../../routeParams'

export function TeacherClassroom({ classroom, onActiveSessionChange, onDeleted }: { classroom: Classroom; onActiveSessionChange?: (session: AttendanceSession | null) => void; onDeleted?: () => void }) {
  const [showDeleteModal, setShowDeleteModal] = useState(false)
  const [cameras, setCameras] = useState<CameraSource[]>([])
  const [sessions, setSessions] = useState<AttendanceSession[]>([])
  const [activeSession, setActiveSession] = useState<AttendanceSession | null>(null)
  const [reviewSession, setReviewSession] = useState<AttendanceSession | null>(null)
  const [attendance, setAttendance] = useState<AttendanceRecord[]>([])
  const [tab, setTab] = useState<'overview' | 'attendance' | 'students'>('overview')
  const [selectedStudentId, setSelectedStudentId] = useState<string | null>(null)
  const [sessionTitle, setSessionTitle] = useState('Morning attendance')
  const [roomCode, setRoomCode] = useState('')
  const [windowMinutes, setWindowMinutes] = useState(1)
  const [graceMinutes, setGraceMinutes] = useState(10)
  const [message, setMessage] = useState('')
  const [sightings, setSightings] = useState<Sighting[]>([])
  const [insights, setInsights] = useState<SessionInsights | null>(null)
  const load = () => api.listSessions(classroom.id).then((nextSessions) => {
    setSessions(nextSessions)
    const live = nextSessions.find((session) => session.status === 'active') ?? null
    setActiveSession(live)
    if (live) setReviewSession(live)
    // Remember the class's room code from its most recent session (active or completed) so it
    // pre-fills next time, until the teacher starts a session with a different code.
    const rememberedRoomCode = live?.room_code ?? nextSessions[0]?.room_code ?? ''
    if (rememberedRoomCode) {
      setRoomCode(rememberedRoomCode)
      void api.listTeacherRoomCameras(rememberedRoomCode).then(setCameras)
    }
  }).catch((e) => setMessage(e.message))
  useEffect(() => {
    // Switching classes must drop the previous class's session-scoped state (review, insights,
    // sightings, room/camera setup) before load() repopulates only what applies to the new one —
    // otherwise load() only ever *sets* these when the new class has a live session, never clears them.
    setActiveSession(null)
    setReviewSession(null)
    setAttendance([])
    setSightings([])
    setInsights(null)
    setCameras([])
    setRoomCode('')
    setSessionTitle('Morning attendance')
    setWindowMinutes(1)
    setGraceMinutes(10)
    setMessage('')
    setShowDeleteModal(false)
    const { classId, studentId } = readQueryParams()
    if (classId === classroom.id && studentId) {
      setSelectedStudentId(studentId)
      setTab('students')
    } else {
      setSelectedStudentId(null)
      setTab('overview')
    }
    void load()
  }, [classroom.id])
  useEffect(() => {
    const onPopState = () => {
      const { classId, studentId } = readQueryParams()
      if (classId !== classroom.id) return
      setSelectedStudentId(studentId)
      if (studentId) setTab('students')
    }
    window.addEventListener('popstate', onPopState)
    return () => window.removeEventListener('popstate', onPopState)
  }, [classroom.id])
  const selectStudent = (nextStudentId: string | null) => {
    setSelectedStudentId(nextStudentId)
    writeQueryParams({ classId: classroom.id, studentId: nextStudentId }, true)
  }
  useEffect(() => { if (!activeSession) { setSightings([]); return }; const refresh = () => Promise.all([api.listSightings(activeSession.id), api.sessionInsights(activeSession.id)]).then(([items, nextInsights]) => { setSightings(items.slice(0, 8)); setInsights(nextInsights) }).catch(() => []); void refresh(); const timer = window.setInterval(refresh, 4000); return () => window.clearInterval(timer) }, [activeSession?.id])
  // eslint-disable-next-line react-hooks/exhaustive-deps -- fire only when the session itself changes, not on every parent render
  useEffect(() => { onActiveSessionChange?.(activeSession) }, [activeSession])
  const start = async () => { try { setMessage(''); const roomCameras = await api.listTeacherRoomCameras(roomCode); setCameras(roomCameras); setActiveSession(await api.startSession(classroom.id, { title: sessionTitle, room_code: roomCode, qualification_window_minutes: windowMinutes, grace_period_minutes: graceMinutes })); await load() } catch (e) { setMessage(e instanceof Error ? e.message : 'Unable to start session.') } }
  const stop = async () => { if (!activeSession) return; try { const completed = await api.stopSession(activeSession.id); setReviewSession(completed); await load(); setTab('attendance'); const [rows, detections] = await Promise.all([api.listAttendance(activeSession.id), api.listSightings(activeSession.id)]); setAttendance(rows); setSightings(detections); setInsights(await api.sessionInsights(activeSession.id).catch(() => null)) } catch (e) { setMessage(e instanceof Error ? e.message : 'Unable to stop session.') } }
  const openAttendance = async (session: AttendanceSession) => { setActiveSession(session.status === 'active' ? session : null); setReviewSession(session); setTab('attendance'); const [rows, detections] = await Promise.all([api.listAttendance(session.id).catch(() => []), api.listSightings(session.id).catch(() => [])]); setAttendance(rows); setSightings(detections); setInsights(await api.sessionInsights(session.id).catch(() => null)) }
  const assignUnknown = async (sightingId: string, studentId: string) => { if (!reviewSession) return; try { await api.assignUnknownSighting(reviewSession.id, sightingId, studentId); const [rows, detections, nextInsights] = await Promise.all([api.listAttendance(reviewSession.id), api.listSightings(reviewSession.id), api.sessionInsights(reviewSession.id)]); setAttendance(rows); setSightings(detections); setInsights(nextInsights); setMessage('Unknown detection assigned. The original event remains in the audit trail.') } catch (e) { setMessage(e instanceof Error ? e.message : 'Unable to assign detection.') } }
  const downloadReport = async () => { if (!reviewSession) return; const blob = await api.downloadReport(reviewSession.id); const url = URL.createObjectURL(blob); const link = document.createElement('a'); link.href = url; link.download = `attendance-${reviewSession.id}.csv`; link.click(); URL.revokeObjectURL(url) }
  return <section className="space-y-6"><div className="rounded-xl border border-[var(--line)] bg-white p-6"><div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start"><div><div className="mb-2 flex items-center gap-2 text-xs font-bold uppercase tracking-[.14em] text-[var(--green)]"><Users size={15} /> Selected class</div><h2 className="text-2xl font-semibold">{classroom.name}</h2><p className="mt-1 text-sm text-[var(--muted)]">{classroom.section || 'No section'} · Join code <strong className="tabular text-[var(--ink)]">{classroom.join_code}</strong></p></div><div className="flex items-center gap-2"><button onClick={() => navigator.clipboard?.writeText(classroom.join_code).then(() => setMessage('Join code copied.'))} className="flex items-center gap-2 rounded-md border border-[var(--line)] px-3 py-2 text-sm font-semibold hover:bg-[#f5f7f4]"><Clipboard size={15} /> Copy code</button><button onClick={() => setShowDeleteModal(true)} disabled={Boolean(activeSession)} title={activeSession ? 'Stop the active session before deleting this class.' : 'Delete class'} className="flex items-center gap-2 rounded-md border border-[var(--line)] px-3 py-2 text-sm font-semibold text-[var(--red)] hover:bg-[var(--red-soft)] disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-transparent"><Trash2 size={15} /> Delete class</button></div></div><div className="mt-6 grid gap-3 sm:grid-cols-3"><Metric label="Cameras" value={String(cameras.filter((camera) => camera.is_enabled).length)} icon={<Video size={17} />} /><Metric label="Sessions" value={String(sessions.length)} icon={<RefreshCw size={17} />} /><Metric label="Status" value={activeSession ? 'Live' : 'Ready'} icon={<span className={`size-2 rounded-full ${activeSession ? 'bg-[#35a86b]' : 'bg-[#a9b3ac]'}`} />} /></div></div>{message && <Notice>{message}</Notice>}<div className="flex gap-1 border-b border-[var(--line)]"><button onClick={() => setTab('overview')} className={`border-b-2 px-4 py-3 text-sm font-bold ${tab === 'overview' ? 'border-[var(--green)] text-[var(--green)]' : 'border-transparent text-[var(--muted)]'}`}>Live setup</button><button onClick={() => setTab('attendance')} className={`border-b-2 px-4 py-3 text-sm font-bold ${tab === 'attendance' ? 'border-[var(--green)] text-[var(--green)]' : 'border-transparent text-[var(--muted)]'}`}>Attendance review</button><button onClick={() => setTab('students')} className={`border-b-2 px-4 py-3 text-sm font-bold ${tab === 'students' ? 'border-[var(--green)] text-[var(--green)]' : 'border-transparent text-[var(--muted)]'}`}>Students</button></div>{tab === 'students' ? <ClassStudents classroom={classroom} studentId={selectedStudentId} onSelectStudent={selectStudent} /> : tab === 'overview' ? <div className="grid gap-6 lg:grid-cols-2"><TeacherCameraPreview active={Boolean(activeSession)} sessionId={activeSession?.id ?? null} cameras={cameras} /><Panel title="Camera sources" action={<span className="text-xs text-[var(--muted)]">Managed by admin</span>}>{cameras.length === 0 ? <Empty text="Enter a room code to load its cameras." /> : cameras.map((camera) => <div key={camera.id} className="flex items-center justify-between gap-3 border-b border-[var(--line)] py-3 last:border-0"><div className="min-w-0"><p className="text-sm font-bold">{camera.label}</p><p className="mt-1 truncate text-xs text-[var(--muted)]">{camera.source_type.replace('_', ' ')} · {camera.source}</p></div><div className="flex shrink-0 items-center gap-2"><span className={`rounded-full px-2 py-1 text-[11px] font-bold ${camera.is_enabled ? 'bg-[var(--green-soft)] text-[var(--green)]' : 'bg-[#edf0ed] text-[var(--muted)]'}`}>{camera.is_enabled ? 'Enabled' : 'Disabled'}</span></div></div>)}</Panel><Panel title="Session control">{activeSession ? <><div className="mb-4 rounded-lg bg-[var(--green-soft)] p-4"><p className="text-sm font-bold text-[var(--green)]">Session is live</p><p className="mt-1 text-xs text-[#478060]">Recognition workers are watching enabled sources.</p></div><button onClick={stop} className="w-full rounded-md bg-[var(--red)] py-3 text-sm font-bold text-white">Stop and calculate attendance</button></> : <><Field label="Session title" value={sessionTitle} onChange={(e) => setSessionTitle(e.target.value)} placeholder="Morning attendance" /><Field label="Room number or code" value={roomCode} onChange={(e) => setRoomCode(e.target.value.toUpperCase())} placeholder="Room 204 or RM204X7K2" /><div className="mt-4 grid gap-4 sm:grid-cols-2"><label className="block"><span className="mb-1.5 block text-xs font-bold uppercase tracking-wide text-[var(--muted)]">Attendance window</span><select value={windowMinutes} onChange={(event) => setWindowMinutes(Number(event.target.value))} className="w-full rounded-md border border-[var(--line)] bg-white px-3.5 py-3 text-sm"><option value={1}>1 minute</option><option value={2}>2 minutes</option><option value={5}>5 minutes</option><option value={10}>10 minutes</option><option value={15}>15 minutes</option><option value={30}>30 minutes</option><option value={60}>60 minutes</option></select><span className="mt-1.5 block text-xs text-[var(--muted)]">One or more detections in a window count once.</span></label><label className="block"><span className="mb-1.5 block text-xs font-bold uppercase tracking-wide text-[var(--muted)]">Arrival grace</span><div className="flex items-center rounded-md border border-[var(--line)] bg-white"><input type="number" min={0} max={120} value={graceMinutes} onChange={(event) => setGraceMinutes(Math.max(0, Math.min(120, Number(event.target.value))))} className="min-w-0 flex-1 rounded-md px-3.5 py-3 text-sm outline-none" /><span className="pr-3 text-xs text-[var(--muted)]">minutes</span></div><span className="mt-1.5 block text-xs text-[var(--muted)]">Controls Present versus Late arrival.</span></label></div><button disabled={!roomCode.trim() || !sessionTitle.trim()} onClick={start} className="mt-4 w-full rounded-md bg-[var(--green)] py-3 text-sm font-bold text-white disabled:opacity-40">Start recognition session</button></>}<div className="mt-6 border-t border-[var(--line)] pt-4"><p className="mb-3 text-xs font-bold uppercase tracking-wide text-[var(--muted)]">Recent sessions</p>{sessions.length === 0 ? <Empty text="No sessions yet." /> : sessions.slice(0, 4).map((session) => <button key={session.id} onClick={() => openAttendance(session)} className="flex w-full items-center justify-between border-b border-[var(--line)] py-2 text-left last:border-0"><span className="text-sm font-semibold">{session.title}</span><span className="text-xs capitalize text-[var(--muted)]">{session.status}</span></button>)}</div></Panel></div> : <AttendancePanel attendance={attendance} session={reviewSession} insights={insights} sightings={sightings} onAssign={assignUnknown} onDownload={downloadReport} />}{activeSession && <Panel title="Recent detections"><div className="space-y-2">{sightings.length === 0 ? <Empty text="Waiting for face detections..." /> : sightings.map((sighting, index) => <div key={`${sighting.student_id ?? 'unknown'}-${sighting.matched_at}-${index}`} className="flex items-center justify-between border-b border-[var(--line)] py-2 last:border-0"><span className={`text-sm font-semibold ${sighting.student_id === null ? 'text-[var(--red)]' : ''}`}>{sighting.student_name}</span><span className="text-xs text-[var(--muted)]">{new Date(sighting.matched_at).toLocaleTimeString()}</span></div>)}</div></Panel>}{insights && <InsightsPanel insights={insights} />}{showDeleteModal && <DeleteClassModal classroom={classroom} onClose={() => setShowDeleteModal(false)} onDeleted={() => { setShowDeleteModal(false); onDeleted?.() }} />}</section>
}
