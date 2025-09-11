from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/")
def root():
    return {"status": "ok"}

@app.get("/version")
def version():
    return {"version": os.getenv("APP_VERSION", "dev")}
