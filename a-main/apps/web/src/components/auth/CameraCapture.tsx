import { useEffect, useRef, useState } from 'react'
import type React from 'react'
import { Camera, CheckCircle2, RotateCcw, ScanFace, X } from 'lucide-react'
import { FaceLandmarker, FilesetResolver, type FaceLandmarkerResult } from '@mediapipe/tasks-vision'

type Pose = 'front' | 'left' | 'right' | 'up' | 'down'

const POSES: Array<{ key: Pose; label: string; instruction: string }> = [
  { key: 'front', label: 'Look straight ahead', instruction: 'Center your face in the oval and look directly at the camera.' },
  { key: 'left', label: 'Turn your head left', instruction: 'Slowly turn your head to your left.' },
  { key: 'right', label: 'Turn your head right', instruction: 'Slowly turn your head to your right.' },
  { key: 'up', label: 'Tilt your head up', instruction: 'Keep your face centered and slowly tilt your head up.' },
  { key: 'down', label: 'Tilt your head down', instruction: 'Keep your face centered and slowly tilt your head down.' },
]
const TOTAL = POSES.length

const LANDMARKER_WASM = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/wasm'
const LANDMARKER_MODEL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task'

export function CameraCapture({ photos, setPhotos }: { photos: Blob[]; setPhotos: (photos: Blob[]) => void }) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const landmarkerRef = useRef<FaceLandmarker | null>(null)
  const animationRef = useRef<number | null>(null)
  const stableSinceRef = useRef<number | null>(null)
  const captureInProgressRef = useRef(false)
  // Neutral eye-to-nose vertical ratio measured while the "front" pose is held.
  // The up/down checks compare against this per-person baseline so the tilt
  // detection is robust to face shape and camera placement.
  const frontVerticalRef = useRef<number | null>(null)
  const [active, setActive] = useState(false)
  const [guided, setGuided] = useState(false)
  const [poseIndex, setPoseIndex] = useState(0)
  const [cameraError, setCameraError] = useState('')
  const [guidance, setGuidance] = useState('Start the camera to begin the guided scan.')
  const currentPose = POSES[poseIndex]

  const stop = () => {
    if (animationRef.current !== null) cancelAnimationFrame(animationRef.current)
    animationRef.current = null
    streamRef.current?.getTracks().forEach((track) => track.stop())
    streamRef.current = null
    setActive(false)
    setGuided(false)
    stableSinceRef.current = null
  }

  const captureCurrentFrame = async () => {
    if (captureInProgressRef.current) return
    captureInProgressRef.current = true
    const video = videoRef.current
    if (!video || !video.videoWidth || photos.length >= TOTAL) { captureInProgressRef.current = false; return }
    const canvas = document.createElement('canvas')
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    canvas.getContext('2d')?.drawImage(video, 0, 0)
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', .92))
    if (!blob) { captureInProgressRef.current = false; return }
    setPhotos([...photos, blob])
    stableSinceRef.current = null
    if (poseIndex === POSES.length - 1) {
      setGuided(false)
      setGuidance(`Scan complete. Review all ${TOTAL} photos before submitting.`)
    } else {
      setPoseIndex((index) => index + 1)
      setGuidance(POSES[poseIndex + 1].instruction)
    }
    captureInProgressRef.current = false
  }

  const poseMatches = (result: FaceLandmarkerResult): boolean => {
    const landmarks = result.faceLandmarks[0]
    if (!landmarks) return false
    const nose = landmarks[1]
    const leftEye = landmarks[33]
    const rightEye = landmarks[263]
    if (!nose || !leftEye || !rightEye) return false
    const eyeDistance = Math.abs(rightEye.x - leftEye.x)
    if (eyeDistance < 0.08) return false
    const centeredNose = (nose.x - leftEye.x) / (rightEye.x - leftEye.x)
    // Vertical nose offset from the eye line, scaled by interocular distance so
    // it stays comparable across distances. Grows when looking down, shrinks
    // when looking up.
    const verticalRatio = (nose.y - (leftEye.y + rightEye.y) / 2) / eyeDistance
    const horizontallyCentered = centeredNose > 0.36 && centeredNose < 0.64
    if (currentPose.key === 'front') {
      const ok = centeredNose > 0.38 && centeredNose < 0.62
      if (ok) frontVerticalRef.current = verticalRatio
      return ok
    }
    if (currentPose.key === 'left') return centeredNose < 0.36
    if (currentPose.key === 'right') return centeredNose > 0.64
    const baseline = frontVerticalRef.current ?? 0.6
    if (currentPose.key === 'up') return horizontallyCentered && verticalRatio <= baseline - 0.1
    return horizontallyCentered && verticalRatio >= baseline + 0.12
  }

  const analyze = (now: number) => {
    const video = videoRef.current
    const landmarker = landmarkerRef.current
    if (!video || !landmarker || !guided || video.readyState < 2) {
      animationRef.current = requestAnimationFrame(analyze)
      return
    }
    const result = landmarker.detectForVideo(video, now)
    const oneFace = result.faceLandmarks.length === 1
    const matches = oneFace && poseMatches(result)
    if (!oneFace) {
      stableSinceRef.current = null
      setGuidance(result.faceLandmarks.length > 1 ? 'Only one face should be visible.' : currentPose.instruction)
    } else if (!matches) {
      stableSinceRef.current = null
      setGuidance(currentPose.instruction)
    } else {
      if (stableSinceRef.current === null) stableSinceRef.current = now
      const elapsed = now - stableSinceRef.current
      setGuidance(elapsed >= 700 ? 'Capturing…' : `${currentPose.label} · hold still`)
      if (elapsed >= 700) void captureCurrentFrame()
    }
    animationRef.current = requestAnimationFrame(analyze)
  }

  const start = async () => {
    try {
      setCameraError('')
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false })
      streamRef.current = stream
      if (!landmarkerRef.current) {
        const vision = await FilesetResolver.forVisionTasks(LANDMARKER_WASM)
        landmarkerRef.current = await FaceLandmarker.createFromOptions(vision, { baseOptions: { modelAssetPath: LANDMARKER_MODEL, delegate: 'GPU' }, runningMode: 'VIDEO', numFaces: 2, outputFaceBlendshapes: false, outputFacialTransformationMatrixes: false })
      }
      frontVerticalRef.current = null
      setPoseIndex(0)
      setGuided(true)
      setActive(true)
      setGuidance(POSES[0].instruction)
    } catch {
      streamRef.current?.getTracks().forEach((track) => track.stop())
      streamRef.current = null
      setCameraError('Camera guidance could not start. You can use image upload instead.')
    }
  }

  const upload = (event: React.ChangeEvent<HTMLInputElement>) => {
    const selected = Array.from(event.target.files ?? []).filter((file) => file.type === 'image/jpeg' || file.type === 'image/png')
    setPhotos([...photos, ...selected].slice(0, TOTAL))
    event.target.value = ''
  }

  const restart = () => { setPhotos([]); frontVerticalRef.current = null; setPoseIndex(0); setGuidance(POSES[0].instruction); if (!active) void start() }

  useEffect(() => { if (active && videoRef.current && streamRef.current) videoRef.current.srcObject = streamRef.current }, [active])
  useEffect(() => { if (guided) animationRef.current = requestAnimationFrame(analyze); return () => { if (animationRef.current !== null) cancelAnimationFrame(animationRef.current) } }, [guided, poseIndex, photos])
  useEffect(() => () => { streamRef.current?.getTracks().forEach((track) => track.stop()); landmarkerRef.current?.close() }, [])

  return <div className="space-y-3"><div className="relative aspect-[3/4] min-h-0 overflow-hidden rounded-lg bg-[#edf1ed] sm:aspect-video sm:min-h-80 lg:aspect-[16/8] lg:min-h-[360px]">{active ? <><video ref={videoRef} autoPlay playsInline muted className="size-full object-contain sm:object-cover" /><div className="pointer-events-none absolute inset-0 grid place-items-center"><div className="h-[78%] w-[58%] rounded-[50%] border-2 border-white/80 shadow-[0_0_0_999px_rgb(23_32_28/20%)] sm:w-[42%]" /></div><div className="absolute left-1/2 top-3 -translate-x-1/2 rounded-full bg-[#17201c]/75 px-3 py-1.5 text-center text-xs font-semibold text-white">{guided ? guidance : 'Scan complete'}</div></> : <div className="grid size-full place-items-center text-center text-sm text-[var(--muted)]"><div><ScanFace size={28} className="mx-auto mb-2" />Guided scan captures front, left, right, up, and down poses</div></div>}</div>{active && <div className="flex flex-wrap items-center justify-between gap-3 text-sm"><span className="font-semibold text-[var(--muted)]">{Math.min(photos.length, TOTAL)}/{TOTAL} poses captured</span><div className="flex items-center gap-4">{guided ? <span className="text-xs font-semibold text-[var(--muted)]">Follow the guidance above</span> : <button type="button" onClick={restart} className="flex items-center gap-1 font-bold text-[var(--green)]"><RotateCcw size={14} /> Scan again</button>}<button type="button" onClick={stop} className="font-bold text-[var(--red)]">Stop camera</button></div></div>} {!active && <div className="flex flex-wrap items-center gap-4 text-sm"><button type="button" onClick={start} disabled={photos.length >= TOTAL} className="flex items-center gap-1 font-bold text-[var(--green)] disabled:opacity-40"><Camera size={15} /> Start guided scan</button><label className="cursor-pointer font-bold text-[var(--green)] hover:underline">Upload images<input type="file" accept="image/jpeg,image/png" multiple onChange={upload} disabled={photos.length >= TOTAL} className="sr-only" /></label></div>}{cameraError && <p className="text-[11px] text-[var(--red)]">{cameraError}</p>}<p className="text-xs text-[var(--muted)]">Camera guidance is optional. You can upload {TOTAL} JPEG/PNG images as a fallback.</p>{photos.length > 0 && <div className="flex flex-wrap gap-2">{photos.map((photo, index) => <button type="button" title={`Remove capture ${index + 1}`} key={index} onClick={() => setPhotos(photos.filter((_, photoIndex) => photoIndex !== index))} className="group relative"><img src={URL.createObjectURL(photo)} className="size-16 rounded-md object-cover ring-1 ring-[var(--line)]" alt={`Reference ${index + 1}`} /><span className="absolute inset-0 hidden place-items-center rounded-md bg-black/50 text-white group-hover:grid"><X size={14} /></span></button>)}{photos.length === TOTAL && <span className="flex items-center gap-1 text-xs font-semibold text-[var(--green)]"><CheckCircle2 size={14} /> Ready for review</span>}</div>}</div>
}
