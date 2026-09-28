require "json"

module Knowledge
  # What a repository is built with, read from its manifests rather than
  # guessed from its code.
  #
  # Lockfiles give exact versions, which is what makes a proposal sound like
  # someone who shipped it ("Rails 7.1", not "Rails"). Package names are mapped
  # to what a client would call them: turbo-rails is Hotwire, h3-js is H3.
  #
  # Checks the repo root and one level down, which is where monorepos keep
  # their frontend/ and backend/.
  module StackDetector
    GROUPS = %w[languages frameworks databases libraries integrations infrastructure].freeze

    RUBY_GEMS = {
      "rails" => [ "frameworks", "Ruby on Rails", :version ],
      "sinatra" => [ "frameworks", "Sinatra" ], "hanami" => [ "frameworks", "Hanami" ],
      "grape" => [ "frameworks", "Grape" ],
      "turbo-rails" => [ "frameworks", "Hotwire (Turbo + Stimulus)" ],
      "stimulus-rails" => [ "frameworks", "Hotwire (Turbo + Stimulus)" ],
      "graphql" => [ "libraries", "graphql-ruby" ],
      "pg" => [ "databases", "PostgreSQL" ], "mysql2" => [ "databases", "MySQL" ],
      "sqlite3" => [ "databases", "SQLite" ], "redis" => [ "databases", "Redis" ],
      "mongoid" => [ "databases", "MongoDB" ], "neighbor" => [ "databases", "pgvector" ],
      "pgvector" => [ "databases", "pgvector" ], "activerecord-postgis-adapter" => [ "databases", "PostGIS" ],
      "searchkick" => [ "databases", "Elasticsearch" ], "elasticsearch" => [ "databases", "Elasticsearch" ],
      "sidekiq" => [ "libraries", "Sidekiq" ], "good_job" => [ "libraries", "GoodJob" ],
      "solid_queue" => [ "libraries", "Solid Queue" ], "resque" => [ "libraries", "Resque" ],
      "delayed_job" => [ "libraries", "Delayed Job" ],
      "devise" => [ "libraries", "Devise" ], "pundit" => [ "libraries", "Pundit" ],
      "cancancan" => [ "libraries", "CanCanCan" ], "rolify" => [ "libraries", "Rolify" ],
      "acts_as_tenant" => [ "libraries", "acts_as_tenant" ], "ros-apartment" => [ "libraries", "Apartment (multi-tenancy)" ],
      "apartment" => [ "libraries", "Apartment (multi-tenancy)" ],
      "activeadmin" => [ "libraries", "ActiveAdmin" ], "administrate" => [ "libraries", "Administrate" ],
      "doorkeeper" => [ "libraries", "Doorkeeper (OAuth)" ], "omniauth" => [ "libraries", "OmniAuth" ],
      "jwt" => [ "libraries", "JWT" ], "paper_trail" => [ "libraries", "PaperTrail" ],
      "friendly_id" => [ "libraries", "FriendlyId" ], "ransack" => [ "libraries", "Ransack" ],
      "pagy" => [ "libraries", "Pagy" ], "kaminari" => [ "libraries", "Kaminari" ],
      "rspec-rails" => [ "libraries", "RSpec" ], "rubocop" => [ "libraries", "RuboCop" ],
      "brakeman" => [ "libraries", "Brakeman" ], "view_component" => [ "libraries", "ViewComponent" ],
      "dry-rb" => [ "libraries", "dry-rb" ], "interactor" => [ "libraries", "Interactor" ],
      "aasm" => [ "libraries", "AASM" ], "geocoder" => [ "libraries", "Geocoder" ],
      "rgeo" => [ "libraries", "RGeo" ], "shrine" => [ "libraries", "Shrine" ],
      "carrierwave" => [ "libraries", "CarrierWave" ], "prawn" => [ "libraries", "Prawn (PDF)" ],
      "wicked_pdf" => [ "libraries", "WickedPDF" ], "chartkick" => [ "libraries", "Chartkick" ],
      "stripe" => [ "integrations", "Stripe" ], "braintree" => [ "integrations", "Braintree" ],
      "paypal-sdk-rest" => [ "integrations", "PayPal" ], "twilio-ruby" => [ "integrations", "Twilio" ],
      "sendgrid-ruby" => [ "integrations", "SendGrid" ], "postmark-rails" => [ "integrations", "Postmark" ],
      "mailgun-ruby" => [ "integrations", "Mailgun" ], "slack-ruby-client" => [ "integrations", "Slack API" ],
      "google-api-client" => [ "integrations", "Google APIs" ], "ruby-openai" => [ "integrations", "OpenAI API" ],
      "anthropic" => [ "integrations", "Anthropic API" ], "langchainrb" => [ "integrations", "LangChain" ],
      "aws-sdk-s3" => [ "infrastructure", "AWS S3" ], "aws-sdk-core" => [ "infrastructure", "AWS" ],
      "google-cloud-storage" => [ "infrastructure", "Google Cloud Storage" ],
      "sentry-ruby" => [ "infrastructure", "Sentry" ], "newrelic_rpm" => [ "infrastructure", "New Relic" ],
      "kamal" => [ "infrastructure", "Kamal" ], "capistrano" => [ "infrastructure", "Capistrano" ]
    }.freeze

    NPM = {
      "next" => [ "frameworks", "Next.js", :version ], "react" => [ "frameworks", "React", :version ],
      "react-native" => [ "frameworks", "React Native" ], "expo" => [ "frameworks", "Expo" ],
      "vue" => [ "frameworks", "Vue.js", :version ], "nuxt" => [ "frameworks", "Nuxt" ],
      "@angular/core" => [ "frameworks", "Angular", :version ], "svelte" => [ "frameworks", "Svelte" ],
      "@sveltejs/kit" => [ "frameworks", "SvelteKit" ], "express" => [ "frameworks", "Express" ],
      "@nestjs/core" => [ "frameworks", "NestJS" ], "fastify" => [ "frameworks", "Fastify" ],
      "electron" => [ "frameworks", "Electron" ], "@ionic/angular" => [ "frameworks", "Ionic" ],
      "@remix-run/react" => [ "frameworks", "Remix" ], "astro" => [ "frameworks", "Astro" ],
      "tailwindcss" => [ "libraries", "Tailwind CSS" ], "@reduxjs/toolkit" => [ "libraries", "Redux Toolkit" ],
      "redux" => [ "libraries", "Redux" ], "@tanstack/react-query" => [ "libraries", "TanStack Query" ],
      "zod" => [ "libraries", "Zod" ], "@trpc/server" => [ "libraries", "tRPC" ],
      "graphql" => [ "libraries", "GraphQL" ], "@apollo/client" => [ "libraries", "Apollo Client" ],
      "@apollo/server" => [ "libraries", "Apollo Server" ], "socket.io" => [ "libraries", "Socket.IO" ],
      "prisma" => [ "libraries", "Prisma" ], "@prisma/client" => [ "libraries", "Prisma" ],
      "typeorm" => [ "libraries", "TypeORM" ], "sequelize" => [ "libraries", "Sequelize" ],
      "drizzle-orm" => [ "libraries", "Drizzle ORM" ], "jest" => [ "libraries", "Jest" ],
      "vitest" => [ "libraries", "Vitest" ], "cypress" => [ "libraries", "Cypress" ],
      "@playwright/test" => [ "libraries", "Playwright" ], "storybook" => [ "libraries", "Storybook" ],
      "three" => [ "libraries", "Three.js" ], "d3" => [ "libraries", "D3" ],
      "h3-js" => [ "libraries", "H3" ], "mapbox-gl" => [ "libraries", "Mapbox GL" ],
      "leaflet" => [ "libraries", "Leaflet" ], "bullmq" => [ "libraries", "BullMQ" ],
      "pg" => [ "databases", "PostgreSQL" ], "mysql2" => [ "databases", "MySQL" ],
      "mongoose" => [ "databases", "MongoDB" ], "mongodb" => [ "databases", "MongoDB" ],
      "redis" => [ "databases", "Redis" ], "ioredis" => [ "databases", "Redis" ],
      "@supabase/supabase-js" => [ "databases", "Supabase" ], "firebase" => [ "infrastructure", "Firebase" ],
      "firebase-admin" => [ "infrastructure", "Firebase" ],
      "@pinecone-database/pinecone" => [ "databases", "Pinecone" ],
      "stripe" => [ "integrations", "Stripe" ], "@stripe/stripe-js" => [ "integrations", "Stripe" ],
      "twilio" => [ "integrations", "Twilio" ], "@sendgrid/mail" => [ "integrations", "SendGrid" ],
      "openai" => [ "integrations", "OpenAI API" ], "@anthropic-ai/sdk" => [ "integrations", "Anthropic API" ],
      "langchain" => [ "integrations", "LangChain" ], "@langchain/core" => [ "integrations", "LangChain" ],
      "livekit-client" => [ "integrations", "LiveKit" ], "@livekit/agents" => [ "integrations", "LiveKit" ],
      "livekit-server-sdk" => [ "integrations", "LiveKit" ], "@deepgram/sdk" => [ "integrations", "Deepgram" ],
      "@aws-sdk/client-s3" => [ "infrastructure", "AWS S3" ], "aws-sdk" => [ "infrastructure", "AWS" ],
      "@google-cloud/storage" => [ "infrastructure", "Google Cloud Storage" ],
      "@sentry/node" => [ "infrastructure", "Sentry" ], "@sentry/react" => [ "infrastructure", "Sentry" ]
    }.freeze

    PYTHON = {
      "django" => [ "frameworks", "Django" ], "fastapi" => [ "frameworks", "FastAPI" ],
      "flask" => [ "frameworks", "Flask" ], "djangorestframework" => [ "libraries", "Django REST Framework" ],
      "sqlalchemy" => [ "libraries", "SQLAlchemy" ], "pydantic" => [ "libraries", "Pydantic" ],
      "celery" => [ "libraries", "Celery" ], "pandas" => [ "libraries", "pandas" ],
      "numpy" => [ "libraries", "NumPy" ], "scikit-learn" => [ "libraries", "scikit-learn" ],
      "torch" => [ "libraries", "PyTorch" ], "tensorflow" => [ "libraries", "TensorFlow" ],
      "geopandas" => [ "libraries", "GeoPandas" ], "shapely" => [ "libraries", "Shapely" ],
      "h3" => [ "libraries", "H3" ], "pytest" => [ "libraries", "pytest" ],
      "psycopg2" => [ "databases", "PostgreSQL" ], "psycopg2-binary" => [ "databases", "PostgreSQL" ],
      "psycopg" => [ "databases", "PostgreSQL" ], "asyncpg" => [ "databases", "PostgreSQL" ],
      "pymongo" => [ "databases", "MongoDB" ], "redis" => [ "databases", "Redis" ],
      "google-cloud-bigquery" => [ "databases", "BigQuery" ], "pinecone-client" => [ "databases", "Pinecone" ],
      "openai" => [ "integrations", "OpenAI API" ], "anthropic" => [ "integrations", "Anthropic API" ],
      "langchain" => [ "integrations", "LangChain" ], "llama-index" => [ "integrations", "LlamaIndex" ],
      "livekit-agents" => [ "integrations", "LiveKit" ], "deepgram-sdk" => [ "integrations", "Deepgram" ],
      "stripe" => [ "integrations", "Stripe" ], "twilio" => [ "integrations", "Twilio" ],
      "boto3" => [ "infrastructure", "AWS" ], "google-cloud-storage" => [ "infrastructure", "Google Cloud Storage" ]
    }.freeze

    FILES = {
      "Dockerfile" => [ "infrastructure", "Docker" ],
      "docker-compose.yml" => [ "infrastructure", "Docker Compose" ],
      "docker-compose.yaml" => [ "infrastructure", "Docker Compose" ],
      "compose.yml" => [ "infrastructure", "Docker Compose" ],
      "fly.toml" => [ "infrastructure", "Fly.io" ], "vercel.json" => [ "infrastructure", "Vercel" ],
      "netlify.toml" => [ "infrastructure", "Netlify" ], "app.json" => [ "infrastructure", "Heroku" ],
      "serverless.yml" => [ "infrastructure", "Serverless Framework" ],
      "cloudbuild.yaml" => [ "infrastructure", "Google Cloud Build" ],
      ".gitlab-ci.yml" => [ "infrastructure", "GitLab CI" ]
    }.freeze

    module_function

    def call(path)
      found = Hash.new { |h, k| h[k] = [] }
      roots(path).each { |dir| detect(dir, found) }
      GROUPS.to_h { |g| [ g, found[g].uniq ] }.reject { |_, v| v.empty? }
    end

    # Most telling first: "Rails 8.0, Stripe" says more than "Ruby, JavaScript".
    DISPLAY_ORDER = %w[frameworks integrations databases libraries infrastructure languages].freeze

    def flatten(stack) = DISPLAY_ORDER.flat_map { |g| Array((stack || {})[g]) }.uniq

    def roots(path)
      base = Pathname.new(path)
      [ base ] + (base.children.select { |c| c.directory? && !c.basename.to_s.start_with?(".") && !Discover::SKIP.include?(c.basename.to_s) } rescue [])
    end

    def detect(dir, found)
      ruby(dir, found)
      javascript(dir, found)
      python(dir, found)
      other_languages(dir, found)
      FILES.each { |file, (group, name)| found[group] << name if dir.join(file).exist? }
      found["infrastructure"] << "Terraform" if Dir[dir.join("*.tf")].any?
      found["infrastructure"] << "GitHub Actions" if dir.join(".github", "workflows").directory?
    end

    def add(found, (group, name, version_flag), version = nil)
      label = version_flag == :version && version.present? ? "#{name} #{major_minor(version)}" : name
      found[group] << label
    end

    def major_minor(version) = version.to_s[/\d+(\.\d+)?/].to_s

    def ruby(dir, found)
      lock = dir.join("Gemfile.lock")
      gemfile = dir.join("Gemfile")
      return unless lock.exist? || gemfile.exist?

      found["languages"] << "Ruby"
      versions = lock.exist? ? lock.read.scan(/^    ([a-z0-9_\-]+) \(([^)]+)\)$/i).to_h : {}
      names = versions.keys.presence || gemfile.read.scan(/^\s*gem\s+["']([^"']+)["']/).flatten
      names.each do |gem|
        key = gem.start_with?("dry-") ? "dry-rb" : gem
        add(found, RUBY_GEMS[key], versions[gem]) if RUBY_GEMS[key]
      end
    rescue StandardError
      nil
    end

    def javascript(dir, found)
      pkg = dir.join("package.json")
      return unless pkg.exist?

      data = JSON.parse(pkg.read)
      deps = (data["dependencies"] || {}).merge(data["devDependencies"] || {})
      found["languages"] << (deps.key?("typescript") || dir.join("tsconfig.json").exist? ? "TypeScript" : "JavaScript")
      found["languages"] << "Node.js" if deps.key?("express") || deps.key?("@nestjs/core") || deps.key?("fastify")
      deps.each do |name, version|
        key = name.start_with?("@livekit/") ? "@livekit/agents" : name
        add(found, NPM[key], version.to_s.gsub(/[\^~>=<v\s]/, "")) if NPM[key]
      end
    rescue StandardError
      nil
    end

    def python(dir, found)
      text = [ "requirements.txt", "requirements/base.txt", "pyproject.toml", "Pipfile", "setup.py" ]
               .map { |f| dir.join(f) }.select(&:exist?).map(&:read).join("\n")
      return if text.blank?

      found["languages"] << "Python"
      text.downcase.scan(/^[\s"']*([a-z0-9_.\-\[\]]+)/).flatten.map { |n| n.sub(/\[.*\]/, "").tr("_", "-") }.uniq.each do |name|
        add(found, PYTHON[name]) if PYTHON[name]
      end
    rescue StandardError
      nil
    end

    def other_languages(dir, found)
      found["languages"] << "Go" if dir.join("go.mod").exist?
      found["languages"] << "PHP" if dir.join("composer.json").exist?
      found["frameworks"] << "Laravel" if dir.join("artisan").exist?
      found["languages"] << "Rust" if dir.join("Cargo.toml").exist?
      if dir.join("pubspec.yaml").exist?
        found["languages"] << "Dart"
        found["frameworks"] << "Flutter"
      end
      found["languages"] << "Swift" if Dir[dir.join("*.xcodeproj")].any? || dir.join("Package.swift").exist?
      found["languages"] << "Kotlin" if dir.join("build.gradle.kts").exist?
      found["languages"] << "Java" if dir.join("pom.xml").exist? || dir.join("build.gradle").exist?
      found["languages"] << "C#" if Dir[dir.join("*.csproj")].any? || Dir[dir.join("*.sln")].any?
    rescue StandardError
      nil
    end
  end
end
