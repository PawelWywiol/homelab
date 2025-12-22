FROM almir/webhook:2.8.2

# Switch to root to install packages
USER root

# Install bash and jq for script compatibility
RUN apk add --no-cache bash jq openssh-client

# Switch back to webhook user
USER webhook
