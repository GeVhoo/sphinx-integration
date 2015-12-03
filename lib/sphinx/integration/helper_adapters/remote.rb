require "rye"

module Sphinx
  module Integration
    module HelperAdapters
      class SshProxy
        DEFAULT_SSH_OPTIONS = {
          quiet: false,
          info: true,
          safe: false,
          debug: false,
          forward_agent: true
        }.freeze

        delegate :file_upload, to: "@servers"

        # options - Hash
        #           :hosts             - Array of String (required)
        #           :port              - Integer ssh port (default: 22)
        #           :user              - String (default: sphinx)
        def initialize(options = {})
          options.reverse_merge!(user: "sphinx", port: 22)

          @servers = Rye::Set.new("servers", parallel: true)

          Array.wrap(options.fetch(:hosts)).each do |host|
            server = Rye::Box.new(host, DEFAULT_SSH_OPTIONS.merge(options.slice(:user, :port)))
            server.stdout_hook = proc { |data| ::ThinkingSphinx.info(data) }
            server.pre_command_hook = proc { |cmd, *| ::ThinkingSphinx.info(cmd) }
            @servers.add_box(server)
          end
        end

        def within(host)
          removed_servers = []
          @servers.boxes.keep_if { |server| server.host == host || (removed_servers << server && false) }
          yield
          @servers.boxes.concat(removed_servers)
        end

        def without(host)
          index = @servers.boxes.index { |x| x.host == host }
          server = @servers.boxes.delete_at(index)
          yield server
          @servers.boxes.insert(index, server)
        end

        def execute(*args)
          options = args.extract_options!
          exit_status = Array.wrap(options.fetch(:exit_status, 0))
          raps = @servers.execute(*args)
          has_errors = false

          raps.each do |rap|
            real_status = rap[0].is_a?(::Rye::Err) ? rap[0].exit_status : rap.exit_status
            unless exit_status.include?(real_status)
              ThinkingSphinx.fatal(rap.inspect)
              has_errors ||= true
            end
          end
          raise "Error in executing #{args.inspect}" if has_errors
        end
      end

      class Remote < Base
        def initialize(*)
          super

          @ssh = SshProxy.new(hosts: hosts, port: config.ssh_port, user: config.user)
        end

        def running?
          !!@ssh.execute("searchd", "--config #{config.config_file}", "--status")
        rescue Rye::Err
          false
        end

        def stop
          @ssh.execute("searchd", "--config #{config.config_file}", "--stopwait")
        end

        def start
          @ssh.execute("searchd", "--config #{config.config_file}")
        end

        def remove_indexes
          remove_files("#{config.searchd_file_path}/*.*")
        end

        def remove_binlog
          return unless config.configuration.searchd.binlog_path.present?
          remove_files("#{config.configuration.searchd.binlog_path}/binlog.*")
        end

        def copy_config
          @ssh.file_upload(config.generated_config_file, config.config_file)
          sql_file = Rails.root.join("config", "sphinx.sql")
          @ssh.file_upload(sql_file.to_s, config.configuration.searchd.sphinxql_state) if sql_file.exist?
        end

        def index(online)
          indexer_args = ["--all", "--config #{config.config_file}"]
          indexer_args << "--rotate" if online

          if hosts.one?
            @ssh.execute("indexer", *indexer_args)
            return
          end

          @ssh.within(reindex_host) do
            indexer_args << "--nohup" if online
            @ssh.execute("indexer", *indexer_args, exit_status: [0, 2])
            if online
              @ssh.execute("for NAME in #{config.searchd_file_path}/*_core.tmp.*; " +
                           'do mv -f "${NAME}" "${NAME/\.tmp\./.new.}"; done')
            end
          end

          files = "#{config.searchd_file_path}/*_core#{".new" if online}.*"
          @ssh.without(reindex_host) do |server|
            @ssh.execute("rsync", "-ptzv", "-e 'ssh -p #{server.opts[:port]}'",
                         "#{server.user}@#{server.host}:#{files} #{config.searchd_file_path}")
          end

          reload if online
        end

        def reload
          @ssh.execute("kill", "-SIGHUP `cat #{config.configuration.searchd.pid_file}`")
        end

        private

        def hosts
          return @hosts if @hosts
          @hosts = Array.wrap(config.address)
          @hosts = @hosts.select { |host| @options[:host] == host } if @options[:host].presence
          @hosts
        end

        def remove_files(pattern)
          @ssh.execute("rm", "-f", pattern)
        end

        def reindex_host
          @reindex_host ||= hosts.first
        end
      end
    end
  end
end
