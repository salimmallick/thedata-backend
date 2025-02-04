from fastapi import FastAPI, HTTPException
import nats
import os
import logging
from typing import Dict

# Configure logging
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

app = FastAPI()

# NATS client
nc = None

@app.on_event("startup")
async def startup_event():
    global nc
    try:
        # Connect to NATS
        nc = await nats.connect(
            os.getenv("NATS_URL", "nats://localhost:4222"),
            token=os.getenv("NATS_AUTH_TOKEN")
        )
        logger.info("Successfully connected to NATS")
    except Exception as e:
        logger.error(f"Failed to connect to NATS: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to initialize NATS connection")

@app.on_event("shutdown")
async def shutdown_event():
    global nc
    if nc:
        await nc.close()
        logger.info("Closed NATS connection")

@app.get("/health")
async def health_check() -> Dict[str, str]:
    if not nc or not nc.is_connected:
        raise HTTPException(status_code=503, detail="NATS connection is not available")
    return {"status": "healthy", "message": "API service is running"} 