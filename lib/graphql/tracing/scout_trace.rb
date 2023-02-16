# frozen_string_literal: true

module GraphQL
  module Tracing
    module ScoutTrace
      include PlatformTrace

      INSTRUMENT_OPTS = { scope: true }

      # @param set_transaction_name [Boolean] If true, the GraphQL operation name will be used as the transaction name.
      #   This is not advised if you run more than one query per HTTP request, for example, with `graphql-client` or multiplexing.
      #   It can also be specified per-query with `context[:set_scout_transaction_name]`.
      def initialize(set_transaction_name: false, **_rest)
        self.class.include(ScoutApm::Tracer)
        @set_transaction_name = set_transaction_name
        super
      end

      {
        "lex" => "lex.graphql",
        "parse" => "parse.graphql",
        "validate" => "validate.graphql",
        "analyze_query" => "analyze.graphql",
        "analyze_multiplex" => "analyze.graphql",
        "execute_multiplex" => "execute.graphql",
        "execute_query" => "execute.graphql",
        "execute_query_lazy" => "execute.graphql",
      }.each do |trace_method, platform_key|
        module_eval <<-RUBY, __FILE__, __LINE__
        def #{trace_method}(**data)
          #{
            if trace_method == "execute_query"
            <<-RUBY
            set_this_txn_name = data[:query].context[:set_scout_transaction_name]
            if set_this_txn_name == true || (set_this_txn_name.nil? && @set_transaction_name)
              ScoutApm::Transaction.rename(transaction_name(data[:query]))
            end
            RUBY
            end
          }

          self.class.instrument("GraphQL", "#{platform_key}", INSTRUMENT_OPTS) do
            super
          end
        end
        RUBY
      end

      def platform_execute_field(platform_key, _data, &block)
        self.class.instrument("GraphQL", platform_key, INSTRUMENT_OPTS, &block)
      end

      def platform_authorized(platform_key, &block)
        self.class.instrument("GraphQL", platform_key, INSTRUMENT_OPTS, &block)
      end

      alias :platform_authorized_lazy :platform_authorized
      alias :platform_resolve_type :platform_authorized
      alias :platform_resolve_type_lazy :platform_authorized

      def platform_field_key(type, field)
        "#{type.graphql_name}.#{field.graphql_name}"
      end

      def platform_authorized_key(type)
        "#{type.graphql_name}.authorized"
      end

      def platform_resolve_type_key(type)
        "#{type.graphql_name}.resolve_type"
      end
    end
  end
end
