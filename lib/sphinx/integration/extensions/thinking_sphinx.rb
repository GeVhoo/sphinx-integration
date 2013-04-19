# coding: utf-8
module Sphinx::Integration::Extensions::ThinkingSphinx
  autoload :ActiveRecord, 'sphinx/integration/extensions/thinking_sphinx/active_record'
  autoload :Attribute, 'sphinx/integration/extensions/thinking_sphinx/attribute'
  autoload :BundledSearch, 'sphinx/integration/extensions/thinking_sphinx/bundled_search'
  autoload :Index, 'sphinx/integration/extensions/thinking_sphinx/index'
  autoload :PostgreSQLAdapter, 'sphinx/integration/extensions/thinking_sphinx/postgresql_adapter'
  autoload :Property, 'sphinx/integration/extensions/thinking_sphinx/property'
  autoload :Search, 'sphinx/integration/extensions/thinking_sphinx/search'
  autoload :Source, 'sphinx/integration/extensions/thinking_sphinx/source'
  autoload :Configuration, 'sphinx/integration/extensions/thinking_sphinx/configuration'

  extend ActiveSupport::Concern

  included do
    DEFAULT_MATCH = :extended2
    include Sphinx::Integration::FastFacet
  end

  module ClassMethods

    def max_matches
      @ts_max_matches ||= ThinkingSphinx::Configuration.instance.configuration.searchd.max_matches || 5000
    end

    def reset_indexed_models
      context.indexed_models.each do |model|
        model.constantize.reset_indexes
      end
    end

    def take_connection
      Sphinx::Integration::Mysql::ConnectionPool.take do |connection|
        yield connection
      end
    end

  end
end