import { useEffect, useState } from 'react'
import type React from 'react'
import { Lock, Plus } from 'lucide-react'
import { api } from '../../api'
import type { AttendanceSession, Classroom } from '../../types'
import { TeacherClassroom } from './TeacherClassroom'
import { AttendanceAssistant } from './AttendanceAssistant'
import { CreateClass } from './CreateClass'
import { Notice, PageHeading } from '../ui/primitives'
import { readQueryParams, writeQueryParams } from '../../routeParams'

export function TeacherDashboard() {
  const [classes, setClasses] = useState<Classroom[]>([]); const [selected, setSelected] = useState<Classroom | null>(null); const [error, setError] = useState(''); const [showCreate, setShowCreate] = useState(false)
  const [lockedClassId, setLockedClassId] = useState<string | null>(null)
  const [lockedClassName, setLockedClassName] = useState<string | null>(null)
  const refresh = () => Promise.all([api.listClasses(), api.activeTeacherSession().catch(() => ({ class_id: null, class_name: null, session_id: null }))]).then(([items, active]) => {
    setClasses(items)
    setLockedClassId(active.class_id)
    setLockedClassName(active.class_name)
    if (!selected && items.length) {
      const requestedId = readQueryParams().classId
      const locked = active.class_id ? items.find((item) => item.id === active.class_id) : undefined
      const match = requestedId ? items.find((item) => item.id === requestedId) : undefined
      const next = locked ?? match ?? items[0]
      setSelected(next)
      writeQueryParams({ classId: next.id, studentId: locked || match ? undefined : null }, false)
    }
  }).catch((e) => setError(e.message))
  useEffect(() => { void refresh() }, [])
  useEffect(() => {
    const onPopState = () => {
      const requestedId = readQueryParams().classId
      if (lockedClassId && requestedId !== lockedClassId) {
        const lockedItem = classes.find((item) => item.id === lockedClassId)
        if (lockedItem) { setSelected(lockedItem); writeQueryParams({ classId: lockedClassId, studentId: null }, false); return }
      }
      const match = requestedId ? classes.find((item) => item.id === requestedId) : null
      if (match) setSelected(match)
    }
    window.addEventListener('popstate', onPopState)
    return () => window.removeEventListener('popstate', onPopState)
  }, [classes, lockedClassId])
  const trySelect = (item: Classroom) => {
    if (lockedClassId && lockedClassId !== item.id) { setError(`Stop the active session in ${lockedClassName ?? 'the current class'} before switching classes.`); return }
    setError('')
    setSelected(item)
    writeQueryParams({ classId: item.id, studentId: null }, true)
  }
  const handleActiveSessionChange = (session: AttendanceSession | null) => { if (!selected) return; setLockedClassId(session ? selected.id : null); setLockedClassName(session ? selected.name : null) }
  const handleClassDeleted = () => {
    if (!selected) return
    const remaining = classes.filter((item) => item.id !== selected.id)
    setClasses(remaining)
    if (lockedClassId === selected.id) { setLockedClassId(null); setLockedClassName(null) }
    const next = remaining[0] ?? null
    setSelected(next)
    writeQueryParams({ classId: next?.id ?? null, studentId: null }, true)
  }
  return <div className="fade-in"><PageHeading eyebrow="Teacher operations" title="Classroom control center" description="Set up your classes, connect camera sources, and run attendance sessions." action={<button onClick={() => setShowCreate(true)} className="flex items-center gap-2 rounded-md bg-[var(--green)] px-4 py-2.5 text-sm font-bold text-white hover:bg-[#0d583c]"><Plus size={16} /> New class</button>} />{error && <Notice tone="error">{error}</Notice>}<div className="mt-8"><AttendanceAssistant classes={classes} /></div><div className="mt-8 grid gap-6 lg:grid-cols-[280px_1fr]"><aside className="space-y-3"><div className="flex items-center justify-between"><h2 className="text-xs font-bold uppercase tracking-[.14em] text-[var(--muted)]">Your classes</h2><span className="tabular text-xs text-[var(--muted)]">{classes.length}</span></div>{classes.length === 0 ? <div className="rounded-xl border border-dashed border-[var(--line)] p-6 text-sm text-[var(--muted)]">Create your first class to begin.</div> : classes.map((item) => { const locked = Boolean(lockedClassId) && lockedClassId !== item.id; return <button key={item.id} onClick={() => trySelect(item)} title={locked ? `Stop the active session in ${lockedClassName ?? 'the current class'} before switching classes.` : undefined} className={`w-full rounded-xl border p-4 text-left transition ${selected?.id === item.id ? 'border-[var(--green)] bg-[var(--green-soft)]' : locked ? 'cursor-not-allowed border-[var(--line)] bg-[#f7f8f6] opacity-50' : 'border-[var(--line)] bg-white hover:border-[#b9c9bd]'}`}><div className="flex items-center justify-between gap-2"><p className="font-bold">{item.name}</p>{lockedClassId === item.id && <Lock size={13} className="shrink-0 text-[var(--green)]" />}</div><p className="mt-1 text-xs text-[var(--muted)]">{item.section || 'No section'} · <span className="tabular">{item.join_code}</span></p></button> })}</aside>{selected ? <TeacherClassroom classroom={selected} onActiveSessionChange={handleActiveSessionChange} onDeleted={handleClassDeleted} /> : <div className="grid min-h-72 place-items-center rounded-xl border border-[var(--line)] bg-white text-sm text-[var(--muted)]">Select a class to manage it.</div>}</div>{showCreate && <CreateClass onClose={() => setShowCreate(false)} onCreated={(item) => { setClasses([item, ...classes]); trySelect(item); setShowCreate(false) }} />}</div>
}
