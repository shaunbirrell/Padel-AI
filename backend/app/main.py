from fastapi import FastAPI, UploadFile, File, HTTPException, status
from uuid import uuid4
import os
from google.cloud import storage

from .config import settings

app = FastAPI(title="Padel Video Analysis Backend", version="0.1.0")

# Initialize Google Cloud Storage client
try:
    storage_client = storage.Client(project=settings.gcp_project_id)
    bucket = storage_client.bucket(settings.gcp_bucket_name)
except Exception as exc:
    # Fail fast if configuration is missing
    raise RuntimeError("Unable to initialize Google Cloud client. Check environment variables.") from exc


@app.get("/")
async def root():
    return {"status": "ok"}


@app.post("/videos/upload", status_code=status.HTTP_201_CREATED)
async def upload_video(file: UploadFile = File(...)):
    """Receive a video file via multipart/form-data and upload it to Cloud Storage.

    Returns the gs:// URI of the stored object.
    """
    allowed_types = {"video/mp4", "video/quicktime", "video/x-msvideo", "video/webm"}
    if file.content_type not in allowed_types:
        raise HTTPException(status_code=400, detail="Unsupported video mime type")

    # Generate unique filename preserving extension
    extension = os.path.splitext(file.filename)[1] if file.filename else ".mp4"
    blob_name = f"videos/{uuid4()}{extension}"

    blob = bucket.blob(blob_name)

    # Upload directly from file-like object
    try:
        blob.upload_from_file(file.file, content_type=file.content_type)
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Failed to upload video to storage") from exc
    finally:
        await file.close()

    gs_uri = f"gs://{settings.gcp_bucket_name}/{blob_name}"

    return {"uri": gs_uri, "object_name": blob_name}