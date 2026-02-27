@echo off
REM Helm Deployment Script with Environment Variables (Windows)
REM This script deploys the backend using Helm with secrets passed via CLI
REM Secrets are NOT hardcoded in YAML files

setlocal enabledelayedexpansion

REM Configuration
set RELEASE_NAME=restaurant-backend
set NAMESPACE=restaurant
set CHART_PATH=.\restaurant-backend

REM Default values
set IMAGE_REPO=your-registry/restaurant-backend
set IMAGE_TAG=latest
set REPLICAS=2

REM Parse command
if [%1]==[] (
    set COMMAND=install
) else (
    set COMMAND=%1
)

if /i "%COMMAND%"=="help" goto :show_usage
if /i "%COMMAND%"=="-h" goto :show_usage
if /i "%COMMAND%"=="--help" goto :show_usage

REM Check required environment variables
echo.
echo Validating environment variables...
echo.

if not defined DB_USER (
    echo Error: DB_USER is not set
    goto :show_usage
)
if not defined DB_HOST (
    echo Error: DB_HOST is not set
    goto :show_usage
)
if not defined DB_PASSWORD (
    echo Error: DB_PASSWORD is not set
    goto :show_usage
)
if not defined DB_NAME (
    echo Error: DB_NAME is not set
    goto :show_usage
)
if not defined DB_PORT (
    echo Error: DB_PORT is not set
    goto :show_usage
)

echo [OK] All required variables are set
echo.

REM Check for namespace flag
if /i "%2"=="--namespace" (
    set NAMESPACE=%3
)

REM Create namespace
kubectl create namespace %NAMESPACE% --dry-run=client -o yaml | kubectl apply -f -

REM Build helm command
set HELM_CMD=helm %COMMAND% %RELEASE_NAME% %CHART_PATH%
set HELM_CMD=!HELM_CMD! -n %NAMESPACE%
set HELM_CMD=!HELM_CMD! --set supabase.user=%DB_USER%
set HELM_CMD=!HELM_CMD! --set supabase.host=%DB_HOST%
set HELM_CMD=!HELM_CMD! --set supabase.password=%DB_PASSWORD%
set HELM_CMD=!HELM_CMD! --set supabase.database=%DB_NAME%
set HELM_CMD=!HELM_CMD! --set supabase.port=%DB_PORT%
set HELM_CMD=!HELM_CMD! --set backend.image.repository=%IMAGE_REPO%
set HELM_CMD=!HELM_CMD! --set backend.image.tag=%IMAGE_TAG%
set HELM_CMD=!HELM_CMD! --set backend.replicas=%REPLICAS%

if /i "%COMMAND%"=="install" (
    set HELM_CMD=!HELM_CMD! --create-namespace
)

if /i "%COMMAND%"=="dry-run" (
    set HELM_CMD=helm install %RELEASE_NAME% %CHART_PATH%
    set HELM_CMD=!HELM_CMD! -n %NAMESPACE%
    set HELM_CMD=!HELM_CMD! --set supabase.user=%DB_USER%
    set HELM_CMD=!HELM_CMD! --set supabase.host=%DB_HOST%
    set HELM_CMD=!HELM_CMD! --set supabase.password=%DB_PASSWORD%
    set HELM_CMD=!HELM_CMD! --set supabase.database=%DB_NAME%
    set HELM_CMD=!HELM_CMD! --set supabase.port=%DB_PORT%
    set HELM_CMD=!HELM_CMD! --set backend.image.repository=%IMAGE_REPO%
    set HELM_CMD=!HELM_CMD! --set backend.image.tag=%IMAGE_TAG%
    set HELM_CMD=!HELM_CMD! --set backend.replicas=%REPLICAS%
    set HELM_CMD=!HELM_CMD! --dry-run --debug
)

REM Display configuration
echo.
echo Deployment Configuration:
echo   Release: %RELEASE_NAME%
echo   Chart: %CHART_PATH%
echo   Namespace: %NAMESPACE%
echo   Command: %COMMAND%
echo   Image: %IMAGE_REPO%:%IMAGE_TAG%
echo   Replicas: %REPLICAS%
echo   Database Host: %DB_HOST%
echo   Database User: %DB_USER%
echo.

if /i not "%COMMAND%"=="dry-run" (
    set /p CONFIRM="Continue? (y/n): "
    if /i not "!CONFIRM!"=="y" (
        echo Cancelled.
        exit /b 1
    )
)

REM Execute helm command
echo.
echo Executing Helm command...
echo.
%HELM_CMD%

if %ERRORLEVEL% equ 0 (
    echo.
    echo [OK] Deployment successful!
    echo.
    echo Check deployment status:
    echo   kubectl get deployments -n %NAMESPACE%
    echo   kubectl get pods -n %NAMESPACE%
    echo   kubectl logs -n %NAMESPACE% -l app=restaurant-backend
) else (
    echo.
    echo [ERROR] Deployment failed!
    exit /b 1
)

exit /b 0

:show_usage
echo.
echo Helm Deployment Script with Environment Variables
echo.
echo Usage: deploy.bat [COMMAND] [OPTIONS]
echo.
echo Commands:
echo   install     Install Helm chart
echo   upgrade     Upgrade existing Helm chart
echo   dry-run     Preview what would be deployed
echo   uninstall   Remove Helm chart
echo.
echo Required Environment Variables:
echo   DB_USER          Supabase user (e.g., postgres.xxx)
echo   DB_HOST          Supabase host (e.g., xxx.supabase.com)
echo   DB_PASSWORD      Supabase password
echo   DB_NAME          Database name (usually 'postgres')
echo   DB_PORT          Database port (usually '6543')
echo.
echo Optional Environment Variables:
echo   IMAGE_REPO       Docker registry (default: your-registry/restaurant-backend)
echo   IMAGE_TAG        Docker image tag (default: latest)
echo   REPLICAS         Number of replicas (default: 2)
echo.
echo Examples:
echo   set DB_USER=postgres.xxx
echo   set DB_HOST=aws-1-ap-south-1.pooler.supabase.com
echo   set DB_PASSWORD=vfY#hEy*tn4_gGj
echo   set DB_NAME=postgres
echo   set DB_PORT=6543
echo   deploy.bat install
echo.
echo   Or load from .env file:
echo   More info in deploy-guide.md
echo.
exit /b 0
