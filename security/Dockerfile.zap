FROM zaproxy/zap-stable:latest

USER root
COPY --chown=zap:zap zap-baseline.conf /zap/wrk/zap-baseline.conf
USER zap
WORKDIR /zap/wrk
