FROM searxng/searxng:2026.2.13-97e572728

# Copy configuration files directly into the image
COPY searxng/settings.yml /etc/searxng/settings.yml
COPY searxng/limiter.toml /etc/searxng/limiter.toml

# Ensure correct permissions
USER root
RUN chmod 644 /etc/searxng/settings.yml /etc/searxng/limiter.toml && \
    chown searxng:searxng /etc/searxng/settings.yml /etc/searxng/limiter.toml

USER searxng
