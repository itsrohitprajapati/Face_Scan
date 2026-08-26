"""Application configuration loaded from environment variables."""

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings for the local development application."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    database_url: str = (
        "postgresql+psycopg://attendance:attendance_dev_password@localhost:5432/"
        "smart_attendance"
    )
    jwt_secret: str = "replace-this-development-secret-before-sharing"
    teacher_invite_code: str = "SMART-TEACHER-DEMO"
    admin_invite_code: str = "SMART-ADMIN-DEMO"
    media_root: Path = Path("storage")
    cors_origins: str = "http://localhost:5173"
    access_token_expire_minutes: int = 480
    openrouter_api_key: str | None = None
    openrouter_model: str = "openai/gpt-4o-mini"
    openrouter_base_url: str = "https://openrouter.ai/api/v1"

    # --- Face recognition (InsightFace: SCRFD detector + ArcFace embeddings) ---
    # Model pack downloaded on first use. "buffalo_l" (w600k_r50) is the most
    # accurate; "buffalo_s" is a lighter MobileFaceNet-class recognizer for
    # constrained hardware. Both emit 512-d embeddings.
    face_model_pack: str = "buffalo_l"
    # Run the ONNX models on a CUDA GPU. Requires `onnxruntime-gpu` installed
    # instead of `onnxruntime`, and a working CUDA/cuDNN toolchain.
    face_use_gpu: bool = False
    # CUDA device index used when face_use_gpu is true (ignored on CPU).
    face_ctx_id: int = 0
    # Square detector input size. Larger => finds smaller/farther faces (better
    # for wide-angle CCTV) at higher CPU/GPU cost. Try 1280/1600/2048 for rooms
    # where students sit far from the lens.
    face_det_size: int = 1024
    # Minimum SCRFD confidence for a detection to be considered a face.
    face_det_threshold: float = 0.5
    # Cosine-similarity threshold for calling a probe the same identity as an
    # enrolled student. Raise toward ~0.5 if you see false matches; lower toward
    # ~0.3 if genuine students are missed (e.g. large enrollment/CCTV gap).
    face_match_similarity: float = 0.40
    # Frames wider than this are downscaled before processing to bound CPU and
    # preview bandwidth. Detection quality is governed by face_det_size, so this
    # mainly caps the aligned-crop resolution feeding the recognizer.
    face_max_frame_width: int = 1600
    # Seconds between recognition passes per camera worker (preview is smoother).
    recognition_sample_interval_seconds: float = 0.5

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
