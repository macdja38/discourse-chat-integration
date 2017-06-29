  
  # Similar to an ActiveRecord class, but uses PluginStore for storage instead. Adapted from discourse-data-explorer
  # Using this means we can use a standard serializer for sending JSON to the client, and also have convenient save/update/delete methods
  # Since this is now being used in two plugins, maybe it should be built into core somehow
  class DiscourseChat::Rule
    attr_accessor :id, :provider, :channel, :category_id, :tags, :filter

    def initialize(h={})
      h.each {|k,v| public_send("#{k}=",v)}
    end

    # saving/loading functions
    def self.alloc_id
      DistributedMutex.synchronize('discourse-chat_rule-id') do
        max_id = DiscourseChat.pstore_get("rule:_id")
        max_id = 1 unless max_id
        DiscourseChat.pstore_set("rule:_id", max_id + 1)
        max_id
      end
    end

    def self.from_hash(h)
      rule = DiscourseChat::Rule.new
      [:provider, :channel, :category_id, :tags, :filter].each do |sym|
        rule.send("#{sym}=", h[sym]) if h[sym]
      end
      if h[:id]
        rule.id = h[:id].to_i
      end
      rule
    end

    def to_hash
      {
        id: @id,
        provider: @provider,
        channel: @channel,
        category_id: @category_id,
        tags: @tags,
        filter: @filter,
      }
    end

    def self.find(id, opts={})
      hash = DiscourseChat.pstore_get("rule:#{id}")
      unless hash
        return DiscourseChat::Rule.new if opts[:ignore_deleted]
        raise Discourse::NotFound
      end
      from_hash hash
    end

    def save
      unless @id && @id > 0
        @id = self.class.alloc_id
      end
      DiscourseChat.pstore_set "rule:#{id}", to_hash
      return self
    end

    def destroy
      DiscourseChat.pstore_delete "rule:#{id}"
    end

    def read_attribute_for_serialization(attr)
      self.send(attr)
    end

    def self.all_for_provider(provider)
      self.where("value::json->>'provider'=?", provider)
    end

    def self.all_for_category(category_id)
      if category_id.nil?
        self.where("json_typeof(value::json->'category_id')='null'")
      else
        self.where("value::json->>'category_id'=?", category_id.to_s)
      end
    end

    # Use JSON selectors like this:
    #    Rule.where("value::json->>'provider'=?", "telegram")
    def self.where(*args)
      rows = self._all_raw.where(*args)
      self._from_psr_rows(rows)
    end

    def self.all
      self._from_psr_rows(self._all_raw)
    end

    def self._all_raw
      PluginStoreRow.where(plugin_name: DiscourseChat.plugin_name)
        .where("key LIKE 'rule:%'")
        .where("key != 'rule:_id'")
    end

    def self._from_psr_rows(raw)
      raw.map do |psr|
        from_hash PluginStore.cast_value(psr.type_name, psr.value)
      end
    end

    def self.destroy_all
      self._all_raw().destroy_all
    end
  end