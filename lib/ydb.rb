# a little wrapper on yaml/store to give collection and record access to a
# transaction yaml store.
#
# sample usage
#
#     require 'ydb'
#
#     ydb = YDB.new
#
#     collection = ydb.collection(:posts)
#
#     2.times do
#       id = collection.create(:k => :v, :array => [0,1,2], :time => Time.now.to_f)
#       record = collection.find(id)
#
#       p record
#         #=> {"k"=>:v, "time"=>1315493211.86451, "id"=>"1", "array"=>[0, 1, 2]}
#         #=> {"k"=>:v, "time"=>1315493211.88372, "id"=>"2", "array"=>[0, 1, 2]}
#     end
#
#     p collection.all
#         #=> [{"k"=>:v, "time"=>1315493211.86451, "array"=>[0, 1, 2], "id"=>"1"}
#         #=> , {"k"=>:v, "time"=>1315493211.88372, "array"=>[0, 1, 2], "id"=>"2"}
#         #=> ]
#
#
#     ydb[:tablename].create(:foo => :bar)
#
#     puts IO.read(ydb.path)
#        #=> ---
#        #=> tablename:
#        #=>   "1":
#        #=>     foo: :bar
#        #=>     id: "1"
#        #=> posts:
#        #=>   "1":
#        #=>     k: :v
#        #=>     time: 1315493211.86451
#        #=>     id: "1"
#        #=>     array:
#        #=>     - 0
#        #=>     - 1
#        #=>     - 2
#        #=>   "2":
#        #=>     k: :v
#        #=>     time: 1315493211.88372
#        #=>     id: "2"
#        #=>     array:
#        #=>     - 0
#        #=>     - 1
#        #=>     - 2

  require 'yaml/store'
  require 'fileutils'

  class YDB
    Version = '0.0.1' unless defined?(Version)

    def YDB.version
      YDB::Version
    end

    def YDB.dependencies
      {
        'map'         =>  [ 'map'         , '~> 4.4.0' ],
      }
    end

    def YDB.libdir(*args, &block)
      @libdir ||= File.expand_path(__FILE__).sub(/\.rb$/,'')
      args.empty? ? @libdir : File.join(@libdir, *args)
    ensure
      if block
        begin
          $LOAD_PATH.unshift(@libdir)
          block.call()
        ensure
          $LOAD_PATH.shift()
        end
      end
    end

    def YDB.load(*libs)
      libs = libs.join(' ').scan(/[^\s+]+/)
      YDB.libdir{ libs.each{|lib| Kernel.load(lib) } }
    end

  # gems
  #
    begin
      require 'rubygems'
    rescue LoadError
      nil
    end

    if defined?(gem)
      YDB.dependencies.each do |lib, dependency|
        gem(*dependency) if defined?(gem)
        require(lib)
      end
    end

    attr_accessor :path

    def initialize(*args)
      options = Map.options_for!(args)
      @path = ( args.shift || options[:path] || YDB.default_path ).to_s
      FileUtils.mkdir_p(File.dirname(@path)) rescue nil
    end

    def rm_f
      FileUtils.rm_f(@path) rescue nil
    end

    def rm_rf
      FileUtils.rm_rf(@path) rescue nil
    end

    def truncate
      rm_f
    end

    def ydb
      self
    end

    def ystore
      @ystore ||= YAML::Store.new(path)
    end

    class Collection
      def initialize(name, ydb)
        @name = name.to_s
        @ydb = ydb
      end

      def save(data = {})
        @ydb.save(@name, data)
      end
      alias_method(:create, :save)
      alias_method(:update, :save)

      def find(id = :all)
        @ydb.find(@name, id)
      end

      def all
        find(:all)
      end

      def [](id)
        find(id)
      end

      def []=(id, data = {})
        data.delete(:id)
        data.delete('id')
        data[:id] = id
        save(data)
      end

      def delete(id)
        @ydb.delete(@name, id)
        id
      end
      alias_method('destroy', 'delete')

      def to_hash
        transaction{|y| y[@name]}
      end

      def size
        to_hash.size
      end
      alias_method('count', 'size')

      def to_yaml(*args, &block)
        Hash.new.update(to_hash).to_yaml(*args, &block)
      end

      def transaction(*args, &block)
        @ydb.ystore.transaction(*args, &block)
      end

    end

    def collection(name)
      Collection.new(name, ydb)
    end
    alias_method('[]', 'collection')

    def method_missing(method, *args, &block)
      if args.empty? and block.nil?
        return self.collection(method)
      end
      super
    end

    def transaction(*args, &block)
      ystore.transaction(*args, &block)
    end

    def save(collection, data)
      data = data_for(data)
      ystore.transaction do |y|
        collection = (y[collection.to_s] ||= {})
        id = next_id_for(collection, data)
        collection[id] = data
        record = collection[id]
        id
      end
    end

    def data_for(data)
      data ? Map.for(data) : nil
    end

    alias_method(:create, :save)

    def find(collection, id = :all, &block)
      ystore.transaction do |y|
        collection = (y[collection.to_s] ||= {})
        if id.nil? or id == :all
          list = collection.values.map{|data| data_for(data)}
          if block
            collection[:all] = list.map{|record| data_for(block.call(record))}
          else
            list
          end
        else
          key = String(id)
          record = data_for(collection[key])
          if block
            collection[key] = data_for(block.call(record))
          else
            record
          end
        end
      end
    end

    def update(collection, id = :all, updates = {})
      data = data_for(data)
      find(collection, id) do |record|
        record.update(updates)
      end
    end

    def delete(collection, id = :all)
      ystore.transaction do |y|
        collection = (y[collection.to_s] ||= {})
        if id.nil? or id == :all
          collection.clear()
        else
          deleted = collection.delete(String(id))
          data_for(deleted) if deleted
        end
      end
    end
    alias_method('destroy', 'delete')

    def next_id_for(collection, data)
      data = data_for(data)
      begin
        id = id_for(data)
        raise if id.strip.empty?
        id
      rescue
        data['id'] = String(collection.size + 1)
        id_for(data)
      end
    end

    def id_for(data)
      data = data_for(data)
      %w( id _id ).each{|key| return String(data[key]) if data.has_key?(key)}
      raise("no id discoverable for #{ data.inspect }")
    end

    def to_hash
      ystore.transaction do |y|
        y.roots.inject(Hash.new){|h,k| h.update(k => y[k])}
      end
    end

    def to_yaml(*args, &block)
      to_hash.to_yaml(*args, &block)
    end

    class << YDB
      attr_writer :root
      attr_writer :instance

      def default_root()
        defined?(Rails.root) && Rails.root ? File.join(Rails.root.to_s, 'db') : '.'
      end

      def default_path()
        File.join(default_root, 'ydb.yml')
      end

      def method_missing(method, *args, &block)
        super unless instance.respond_to?(method)
        instance.send(method, *args, &block)
      end

      def instance
        @instance ||= YDB.new(YDB.default_path)
      end

      def root
        @root ||= default_root
      end

      def tmp(&block)
        require 'tempfile' unless defined?(Tempfile)
        tempfile = Tempfile.new("#{ Process.pid }-#{ Process.ppid }-#{ Time.now.to_f }-#{ rand }")
        path = tempfile.path
        ydb = new(:path => path)
        if block
          begin
            block.call(ydb)
          ensure
            ydb.rm_rf
          end
        else
          ydb
        end
      end
    end
  end

  Ydb = YDb = YDB
