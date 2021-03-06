require "sinatra"
require "yaml"
require "smart_proxy_reports/reports"
require "smart_proxy_reports/processor"
require "smart_proxy_reports/puppet_processor"
require "smart_proxy_reports/ansible_processor"

module Proxy::Reports
  class Api < ::Sinatra::Base
    include ::Proxy::Log
    include ::Proxy::Util
    helpers ::Proxy::Helpers
    authorize_with_trusted_hosts
    authorize_with_ssl_client

    before do
      content_type "application/json"
    end

    def check_content_type(format)
      request_type = request.env["CONTENT_TYPE"]
      if format == "puppet"
        log_halt(415, "Content type must be application/x-yaml, was: #{request_type}") unless request_type.start_with?("application/x-yaml")
      elsif format == "ansible"
        log_halt(415, "Content type must be application/json, was: #{request_type}") unless request_type.start_with?("application/json")
      else
        log_halt(415, "Unknown format: #{format}")
      end
    end

    EXTS = {
      puppet: "yaml",
      ansible: "json",
    }.freeze

    def save_payload(input, format)
      filename = File.join(Proxy::Reports::Plugin.settings.incoming_save_dir, "#{format}-#{Time.now.to_f}.#{EXTS[format.to_sym]}")
      File.open(filename, "w") { |f| f.write(input) }
    end

    post "/:format" do
      format = params[:format]
      log_halt(404, "Format argument not specified") unless format
      check_content_type(format)
      input = request.body.read
      save_payload(input, format) if Proxy::Reports::Plugin.settings.incoming_save_dir
      log_halt(415, "Missing body") if input.empty?
      json_body = to_bool(params[:json_body], true)
      processor = Processor.new_processor(format, input, json_body: json_body)
      status 202
      processor.spool_report
    rescue => e
      log_halt 415, e, "Error during report processing: #{e.message}"
    end
  end
end
