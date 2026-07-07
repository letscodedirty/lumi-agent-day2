"""
서버 상태 확인 엔드포인트

Production 환경에서 필수적인 헬스체크 API입니다.
로드밸런서, 쿠버네티스 등에서 서버 상태를 확인할 때 사용합니다.

엔드포인트:
    GET /health/         - 기본 헬스체크
    GET /health/ready    - 준비 상태 확인 (DB 연결 등)
"""

from datetime import datetime

from fastapi import APIRouter

from app.core.config import settings

# TODO 1: APIRouter 인스턴스 생성
router = APIRouter()


# TODO 2: 헬스체크 엔드포인트 구현
@router.get("/")
async def health_check() -> dict:
    """
    기본 헬스체크 엔드포인트

    서버가 살아있는지 확인합니다. (Liveness Probe)
    로드밸런서, Docker HEALTHCHECK, CD 파이프라인에서 사용됩니다.

    Returns:
        dict: 서버 상태 정보 (status, timestamp, version 포함)
    """
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": "0.5.0",
        "service": "lumi-agent",
        "environment": settings.environment,
    }


@router.get("/ready")
async def readiness_check() -> dict:
    """
    준비 상태 확인 엔드포인트 (Readiness Probe)

    서버가 트래픽을 받을 준비가 되었는지 확인합니다.
    필수 설정(LLM API 키, DB 연결 정보)이 갖춰졌는지 점검합니다.

    Returns:
        dict: 준비 상태 및 개별 체크 결과
    """
    checks = {
        "llm_api": bool(settings.upstage_api_key),
        "database": bool(settings.supabase_url and settings.supabase_key),
    }

    return {
        "status": "ready" if all(checks.values()) else "degraded",
        "timestamp": datetime.now().isoformat(),
        "checks": checks,
    }
