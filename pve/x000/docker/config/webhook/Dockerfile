FROM almir/webhook:2.8.2

# Switch to root to install packages
USER root

# Install bash, jq, openssh-client, and curl for script compatibility
RUN apk add --no-cache bash jq openssh-client curl

# Switch back to webhook user
USER webhook
