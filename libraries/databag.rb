# coding: UTF-8
#
# Cookbook Name:: cerner_splunk
# File Name:: databag.rb

require 'chef/data_bag_item'

module CernerSplunk #:nodoc:
  # This module has methods and classes dealing with databags
  module DataBag
    # Converts a string of the form "(data_bag/)bag_item(:key)" to an array of [data_bag,bag_item,key]
    # If provided nil, will return nil
    def self.to_a(string, options = {})
      opts = {
        default: nil,
        nil_is_default: false,
        default_empty_key: true,
        strip_key: true
      }.merge(options)
      case string
      when nil
        opts[:nil_is_default] ? opts[:default] : nil
      when %r{^(?:(?<bag>[^/:]*)/)?(?<item>[^:]*)(?::(?<key>.*))?$}
        # This Regex will match any string. The Item field is the only one guaranteed to be non-nil
        # Key will contain all content after the first : in a string (if it exists)
        # Bag will only contain content prior to the first / not already contained in key
        # Item is what remains.
        # Some Examples:
        # # '' => [nil, "", nil]
        # # ':' => [nil, "", ""]
        # # '/' => ["", "", nil]
        # # ':/' => [nil, "", "/"]
        # # '/:' => ["", "", ""]
        # # 'foo' => [nil, "foo", nil]
        # # ':foo' => [nil, "", "foo"]
        # # 'foo/' => ["foo", "", nil]
        # # ':foo/bar' => [nil, "", "foo/bar"]
        # # 'foo/bar:baz' => ["foo", "bar", "baz"]
        default = opts[:default] || []
        data = Regexp.last_match
        bag = process(data[:bag], default[0], true, true)
        item = process(data[:item], default[1], true, true)
        key = process(data[:key], default[2], opts[:strip_key], opts[:default_empty_key])
        [bag, item, key]
      else
        fail "Unexpected argument of type #{string.class}: #{string}"
      end
    end

    # Converts an array of the form [data_bag,bag_item,key] to a string of the form "(data_bag/)bag_item(:key)"
    # If provided nil, will return nil
    # Inverse of to_a
    # rubocop:disable CyclomaticComplexity
    def self.to_value(array, _options = {})
      case array
      when nil
        nil
      when Array
        fail "Array '#{array}' can only contain Strings or nil" unless array.all? { |i| i.nil? || i.is_a?(String) }
        data_bag, bag_item, key = array
        Chef::DataBag.validate_name!(data_bag) if data_bag
        Chef::DataBagItem.validate_id!(bag_item) if bag_item

        str = bag_item.to_s
        str = "#{data_bag}/#{str}" if data_bag
        str = "#{str}:#{key}" if key
        str
      else
        fail "Unexpected argument of type #{array.class}: #{array}"
      end
    end
    # rubocop:enable CyclomaticComplexity

    # Loads a data_bag item / based on the string
    # If provided nil or a string that doesn't resolve to a data_bag + item at least will return nil
    # rubocop:disable CyclomaticComplexity
    def self.load(string, options = {})
      opts = {
        type: :simple,
        pick_context: nil,
        handle_load_failure: false
      }.merge(options)
      clazz =
        case opts[:type]
        when :simple
          Chef::DataBagItem
        when :vault
          require 'chef-vault'
          ChefVault::Item
        else
          fail "Unexpected type of DataBag #{opts[:type]}"
        end

      data_bag, bag_item, key = to_a(string, options)
      value =
        if data_bag && bag_item
          # Exception handler to check if data_bag or data_bag_item exists
          begin
            bag = clazz.load(data_bag, bag_item)
            key ? bag[key] : bag
          rescue => e
            raise e unless opts[:handle_load_failure]
            Chef::Log.warn "Could not load the data bag item referenced by: #{to_value([data_bag, bag_item])}. Details available at debug log level, continuing chef run assuming nil."
            Chef::Log.debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}" if Chef::Log.level == :debug
            nil
          end
        end

      if value && opts[:pick_context]
        key = opts[:pick_context].find { |x| value.key?(x.to_s) }
        resolve(value, key.to_s) if key
      else
        value
      end
    end
    # rubocop:enable CyclomaticComplexity

    private

    # Process a string. Helper for the to_a method, Not part of the public API
    def self.process(string, default, strip, default_empty)
      if string
        string.strip! if strip
        string = nil if string.empty? && default_empty
      end
      string ? string : default
    end

    # Finds a particular value in a hash by key, Not part of the public API
    def self.resolve(data_bag_item, key)
      attempts = [key]
      value = data_bag_item[key]
      while value.is_a? String
        if attempts.include? value
          fail "Circular reference resolving key (#{attempts.join(';')})!"
        end
        attempts << value
        value = data_bag_item[value]
      end
      value
    end
  end
end