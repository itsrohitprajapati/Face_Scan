export type UserRole = 'admin' | 'teacher' | 'student'
export type AttendanceStatus = 'present' | 'late' | 'absent'
export type SessionStatus = 'active' | 'completed'
export type CameraSourceType = 'webcam' | 'ip_stream' | 'video_file'

export interface User {
  id: string
  email: string
  full_name: string
  role: UserRole
  roll_number: string | null
  enrollment_complete: boolean
  created_at: string
}

export interface AuthSession {
  access_token: string
  token_type: string
  user: User
}

export interface Classroom {
  id: string
  name: string
  section: string | null
  join_code: string
  teacher_name: string
  created_at: string
}

export interface Room {
  id: string
  name: string
  room_code: string
  is_active: boolean
  camera_count: number
  enabled_camera_count: number
  active_session_id: string | null
  active_session_title: string | null
  created_at: string
}
export interface CameraSource {
  id: string
  label: string
  source_type: CameraSourceType
  source: string
  is_enabled: boolean
  created_at: string
  updated_at: string
}

export interface AttendanceSession {
  id: string
  room_id: string | null
  room_name: string | null
  room_code: string | null
  class_id: string
  title: string
  status: SessionStatus
  started_at: string
  ended_at: string | null
  grace_period_minutes: number
  minimum_sightings: number
  qualification_window_minutes: number
  presence_threshold_percentage: number
}

export interface AttendanceOverride {
  id: string
  status: AttendanceStatus
  reason: string
  teacher_id: string
  teacher_name: string
  created_at: string
}

export interface AttendanceRecord {
  student_id: string
  student_name: string
  roll_number: string
  automated_status: AttendanceStatus
  effective_status: AttendanceStatus
  qualifying_at: string | null
  observed_windows: number
  eligible_windows: number
  presence_percentage: number
  latest_override: AttendanceOverride | null
  override_history: AttendanceOverride[]
}

export interface AttendanceSummary {
  total_sessions: number
  attended_sessions: number
  present_sessions: number
  late_sessions: number
  absent_sessions: number
  attendance_percentage: number
  history: AttendanceHistoryEntry[]
}

export interface AttendanceHistoryEntry {
  session_id: string
  class_id: string
  class_name: string
  session_title: string
  session_started_at: string
  session_ended_at: string | null
  automated_status: AttendanceStatus
  effective_status: AttendanceStatus
  qualifying_at: string | null
  observed_windows: number
  eligible_windows: number
  presence_percentage: number
}

export interface AttendanceQueryRow {
  session_id: string
  class_id: string
  class_name: string
  session_title: string
  session_started_at: string
  session_ended_at: string | null
  student_id: string
  student_name: string
  roll_number: string
  automated_status: AttendanceStatus
  effective_status: AttendanceStatus
  observed_windows: number
  eligible_windows: number
  presence_percentage: number
}

export interface AttendanceQueryData {
  interpretation: {
    summary: string
    start_date: string | null
    end_date: string | null
    status: AttendanceStatus | null
    student_name: string | null
    class_name: string | null
  }
  total_matches: number
  present_count: number
  late_count: number
  absent_count: number
  average_presence_percentage: number
  rows: AttendanceQueryRow[]
}

export interface AttendanceAssistantResponse {
  answer: string
  data: AttendanceQueryData | null
}

export interface Sighting {
  id: string
  student_id: string | null
  student_name: string
  camera_source_id: string
  matched_at: string
  face_distance: number | null
  assigned_student_id: string | null
  assigned_student_name: string | null
}

export interface StudentInsight {
  student_id: string
  student_name: string
  roll_number: string
  automated_status: AttendanceStatus
  effective_status: AttendanceStatus
  observed_windows: number
  eligible_windows: number
  presence_percentage: number
  first_seen_at: string | null
  last_seen_at: string | null
  cameras_seen: number
  review_reasons: string[]
}

export interface TimelineEvent {
  student_name: string
  camera_source_id: string
  matched_at: string
}

export interface CameraInsight {
  camera_source_id: string
  label: string
  sightings: number
  students_seen: number
  last_frame_at: string | null
  status: string
}

export interface SessionInsights {
  session_id: string
  session_title: string
  duration_seconds: number
  timeline: TimelineEvent[]
  students: StudentInsight[]
  cameras: CameraInsight[]
  review_queue: StudentInsight[]
}
