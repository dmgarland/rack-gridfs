require 'timeout'
require 'mongo'

module Rack
  class GridFSConnectionError < StandardError ; end
  class GridFS
    attr_reader :hostname, :port, :database, :prefix, :db

    def initialize(app, options = {})
      options = {
        :hostname => 'localhost',
        :prefix   => 'gridfs',
        :port     => Mongo::Connection::DEFAULT_PORT,
      }.merge(options)

      @app        = app
      @hostname   = options[:hostname]
      @port       = options[:port]
      @database   = options[:database]
      @prefix     = options[:prefix]
      @db         = nil

      connect!
    end

    def call(env)
      request = Rack::Request.new(env)
      if request.path_info =~ /^\/#{prefix}\/(.+)$/
        gridfs_request($1, request)
      else
        @app.call(env)
      end
    end

    def gridfs_request(id, request)
      file = Mongo::Grid.new(db).get(BSON::ObjectId.from_string(id.split(".").first))
      
      if request.env['HTTP_IF_NONE_MATCH'] == file.files_id.to_s || request.env['HTTP_IF_MODIFIED_SINCE'] == file.upload_date.httpdate
        [304, {'Content-Type' => 'text/plain', 'Etag' => file.files_id.to_s}, ['Not modified']]
      else
        [200, {'Content-Type' => file.content_type, 'Last-Modified' => file.upload_date.httpdate, 'Etag' => file.files_id.to_s}, [file.read]]
      end      
    rescue Mongo::GridError, BSON::InvalidObjectId
      [404, {'Content-Type' => 'text/plain'}, ['File not found.']]
    end

    private
      def connect!
        Timeout::timeout(5) do
          @db = Mongo::Connection.new(hostname).db(database)
        end
      rescue Exception => e
        raise Rack::GridFSConnectionError, "Unable to connect to the MongoDB server (#{e.to_s})"
      end
  end
end
