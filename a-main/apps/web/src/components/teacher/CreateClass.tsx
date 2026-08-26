import { useState } from 'react'
import type React from 'react'
import { api } from '../../api'
import type { Classroom } from '../../types'
import { Field, Modal, Notice } from '../ui/primitives'

export function CreateClass({ onClose, onCreated }: { onClose: () => void; onCreated: (item: Classroom) => void }) { const [name, setName] = useState(''); const [section, setSection] = useState(''); const [error, setError] = useState(''); const submit = async (e: React.FormEvent) => { e.preventDefault(); try { onCreated(await api.createClass(name, section)) } catch (e) { setError(e instanceof Error ? e.message : 'Unable to create class.') } }; return <Modal title="Create a class" onClose={onClose}><form onSubmit={submit} className="space-y-4"><Field label="Class name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Data Structures" required /><Field label="Section" value={section} onChange={(e) => setSection(e.target.value)} placeholder="CSE-A" />{error && <Notice tone="error">{error}</Notice>}<button className="w-full rounded-md bg-[var(--green)] py-3 text-sm font-bold text-white">Create class</button></form></Modal> }
