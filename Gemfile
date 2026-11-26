# frozen_string_literal: true
# Single source of truth: .ruby-version. A duplicated range here can drift from the version
# actually installed and used by CI and by build-docs.sh.
ruby file: '.ruby-version'

source "https://rubygems.org"
gem 'asciidoctor', '2.0.23'
gem 'pygments.rb', '3.0'
# asciidoctor loads these from the standard library, which warns on every docs build that Ruby 3.5
# stops shipping them as default gems. Listing them here loads the gems instead.
gem 'logger', '1.7.0'
gem 'ostruct', '0.6.3'
