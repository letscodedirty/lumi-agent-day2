# Production 배포를 위한 Dockerfile
# uv 패키지 관리자를 사용한 최적화된 이미지 빌드
#
# 빌드 방법:
#   docker build -t lumi-agent .
#
# 실행 방법:
#   docker run -p 8000:8000 --env-file .env lumi-agent
#
# 핵심 포인트:
#   1. uv를 사용한 빠른 의존성 설치
#   2. 멀티스테이지 빌드로 이미지 크기 최적화
#   3. non-root 유저로 보안 강화

# Stage 1: 빌드 스테이지
FROM python:3.11-slim AS builder

WORKDIR /app

# uv 설치 (astral-sh에서 제공하는 공식 이미지에서 복사)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# 의존성 파일 먼저 복사 (캐시 레이어 활용)
# pyproject.toml이나 uv.lock이 변경되지 않으면 이 레이어는 캐시됨
# README.md: pyproject.toml의 readme 설정에 필요
COPY pyproject.toml uv.lock* README.md ./

# TODO 1: 의존성 설치 명령어 작성
# --frozen: uv.lock에 고정된 버전 그대로 설치 (재현 가능한 빌드)
# --no-dev: dev 의존성(pytest, ruff 등) 제외 → 이미지 크기 최적화
# --no-install-project: 의존성만 먼저 설치 (코드 변경 시에도 이 레이어는 캐시 유지)
RUN uv sync --frozen --no-dev --no-install-project

# Stage 2: 런타임 스테이지
FROM python:3.11-slim AS runtime

WORKDIR /app

# 런타임에 필요한 시스템 패키지 설치
# curl: 헬스체크용
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# uv 복사 (런타임에서도 uv run 사용)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# 빌드 스테이지에서 설치된 의존성 복사
COPY --from=builder /app/.venv /app/.venv

# 애플리케이션 코드 복사
COPY app/ ./app/
COPY data/ ./data/

# pyproject.toml, README.md 복사 (uv run에 필요)
COPY pyproject.toml README.md ./

# TODO 2: 보안 설정 - non-root 유저 생성 및 권한 설정
# 시스템 그룹/유저 생성 (로그인 불가능한 서비스 계정)
RUN groupadd --system appuser \
    && useradd --system --gid appuser --create-home appuser \
    && chown -R appuser:appuser /app

# non-root 유저로 전환
USER appuser

# 환경변수 설정
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:$PATH"

# TODO 3: 헬스체크 설정
# 30초마다 헬스체크 엔드포인트를 호출하여 컨테이너 상태 확인
# start-period: 앱 초기화(그래프 컴파일 등) 시간을 고려한 유예 기간
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/api/v1/health/ || exit 1

# 포트 노출
EXPOSE 8000

# TODO 4: 서버 실행 명령어 작성(uv run)
CMD ["uv", "run", "--no-sync", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

