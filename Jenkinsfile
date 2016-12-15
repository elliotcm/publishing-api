#!/usr/bin/env groovy

REPOSITORY = 'publishing-api'

node {
  def govuk = load '/var/lib/jenkins/groovy_scripts/govuk_jenkinslib.groovy'
  def content_schemas_path = "${WORKSPACE}/govuk-content-schemas"
  def commit_id = ''
  def ruby_version = ''

  try {
    stage("Checkout") {
      checkout scm
      sh """
        rm -rf ${content_schemas_path} && \
        mkdir ${content_schemas_path} && \
        curl -fsSL https://github.com/alphagov/govuk-content-schemas/archive/deployed-to-production.tar.gz | \
          tar xz --strip-components=1 -C ${content_schemas_path}
      """
      commit_id = sh returnStdout: true, script: 'git rev-parse HEAD'
      ruby_version = readFile('.ruby-version')
    }

    withEnv(["GOVUK_CONTENT_SCHEMAS_PATH=${content_schemas_path}",'RAILS_ENV=test',"RBENV_VERSION=${ruby_version}"]) {
      stage("Build") {
        parallel (
          native: {
            sh "bundle install --path '${HOME}/bundles/${REPOSITORY}' --deployment --without development"
          },
          docker: {
            sh "git archive HEAD | docker build - -t ${REPOSITORY}:${commit_id}"
          }
        )
      }

      stage("Lint") {
        sh 'bundle exec govuk-lint-ruby app config Gemfile lib spec'
      }

      stage("Test") {
        parallel (
          native: {
            sh 'bin/rails db:environment:set db:drop db:create db:schema:load'
            sh 'bin/rake'
          },
          docker: {
            sh "docker run ${REPOSITORY}:${commit_id} bin/rails db:environment:set db:drop db:create db:schema:load"
            sh "docker run ${REPOSITORY}:${commit_id} bin/rake"
          }
        )
      }
    }
  } catch (e) {
    currentBuild.result = "FAILED"
    step([$class: 'Mailer',
          notifyEveryUnstableBuild: true,
          recipients: 'govuk-ci-notifications@digital.cabinet-office.gov.uk',
          sendToIndividuals: true])
    throw e
  }
}
