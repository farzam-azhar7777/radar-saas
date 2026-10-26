FROM ruby:3.4.5-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git curl ca-certificates procps libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

RUN git config --system --add safe.directory '*'

RUN useradd --create-home --uid 1000 --shell /bin/bash radar
USER radar
ENV HOME=/home/radar \
    PATH=/home/radar/.local/bin:$PATH \
    RAILS_ENV=development \
    BUNDLE_PATH=/home/radar/bundle \
    PORT=8586

RUN curl -fsSL https://claude.ai/install.sh | bash && claude --version

WORKDIR /rails

COPY --chown=radar:radar Gemfile Gemfile.lock .ruby-version ./
RUN bundle install --jobs 4 && rm -rf "$BUNDLE_PATH"/ruby/*/cache

COPY --chown=radar:radar . .

RUN bin/rails tailwindcss:build && rm -rf storage/* log/* tmp/cache

EXPOSE 8586
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "8586"]
