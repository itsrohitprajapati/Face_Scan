import { useEffect, useState } from 'react'
import { api, ApiError } from '../../api'
import type { CameraSource } from '../../types'
import { Panel } from '../ui/primitives'

export function TeacherCameraPreview({ active, sessionId, cameras }: { active: boolean; sessionId: string | null; cameras: CameraSource[] }) {
  const enabledCameras = cameras.filter((camera) => camera.is_enabled)
  const [selectedCameraId, setSelectedCameraId] = useState('')
  const selectedCamera = enabledCameras.find((camera) => camera.id === selectedCameraId) ?? enabledCameras[0]
  const [frameUrl, setFrameUrl] = useState(''); const [error, setError] = useState('')
  useEffect(() => { if (selectedCamera && selectedCamera.id !== selectedCameraId) setSelectedCameraId(selectedCamera.id) }, [selectedCamera?.id, selectedCameraId])
  useEffect(() => {
    setFrameUrl(''); setError('')
    if (!active || !sessionId || !selectedCamera) return
    let cancelled = false; let currentUrl = ''; let loading = false
    const loadFrame = async () => { if (loading) return; loading = true; try { const blob = await api.previewCamera(sessionId, selectedCamera.id); if (cancelled) return; const nextUrl = URL.createObjectURL(blob); if (currentUrl) URL.revokeObjectURL(currentUrl); currentUrl = nextUrl; setFrameUrl(nextUrl); setError('') } catch (e) { if (!cancelled && e instanceof ApiError && e.status !== 404) setError(e.message) } finally { loading = false } }
    void loadFrame(); const timer = window.setInterval(() => void loadFrame(), 150)
    return () => { cancelled = true; window.clearInterval(timer); if (currentUrl) URL.revokeObjectURL(currentUrl) }
  }, [active, sessionId, selectedCamera?.id])
  return <Panel title="Camera feed" action={<span className={`flex items-center gap-1.5 text-xs font-bold ${active ? 'text-[var(--green)]' : 'text-[var(--muted)]'}`}><span className={`size-2 rounded-full ${active ? 'bg-[#35a86b]' : 'bg-[#a9b3ac]'}`} />{active ? 'Live' : 'Standby'}</span>}>
    {enabledCameras.length > 1 && <label className="mb-3 block"><span className="mb-1.5 block text-[10px] font-bold uppercase tracking-wide text-[var(--muted)]">View source</span><select value={selectedCamera?.id ?? ''} onChange={(event) => setSelectedCameraId(event.target.value)} className="w-full rounded-md border border-[var(--line)] bg-white px-3 py-2 text-sm font-semibold outline-none focus:border-[var(--green)]">{enabledCameras.map((camera) => <option key={camera.id} value={camera.id}>{camera.label} · {camera.source_type.replace('_', ' ')}</option>)}</select></label>}
    <div className="relative aspect-video overflow-hidden rounded-lg bg-[#17201c]">{frameUrl ? <img src={frameUrl} alt={`Live feed from ${selectedCamera?.label ?? 'camera'}`} className="size-full object-contain" /> : <div className="grid size-full place-items-center p-5 text-center text-xs leading-5 text-[#b8c5bc]">{error || (!selectedCamera ? 'Enable a camera source to preview the feed.' : active ? `Waiting for ${selectedCamera.label}. Check that its ${selectedCamera.source_type.replace('_', ' ')} address is reachable from the API server.` : 'Start a session to view the camera feed.')}</div>}{frameUrl && <><div className="absolute bottom-2 left-2 rounded bg-[#17201c]/75 px-2 py-1 text-[11px] font-semibold text-white">{selectedCamera?.label} · {selectedCamera?.source_type.replace('_', ' ')}</div><div className="absolute right-2 top-2 rounded bg-[#17201c]/75 px-2 py-1 text-[10px] text-white"><span className="text-[#65d281]">Green</span> recognized · <span className="text-[#ff8b8b]">Red</span> unknown</div></>}</div>
  </Panel>
}
