# ~*~ encoding: utf-8 ~*~
require 'digest/sha1'
require 'cgi'
require 'pygments'
require 'base64'

require File.expand_path '../helpers', __FILE__

# initialize Pygments
Pygments.start

module Gollum

  class Markup
    include Helpers

    @formats = {}

    class << self
      attr_reader :formats

      # Register a file extension and associated markup type
      #
      # ext     - The file extension
      # name    - The name of the markup type
      # options - Hash of options:
      #           regexp - Regexp to match against.
      #                    Defaults to exact match of ext.
      #
      # If given a block, that block will be registered with GitHub::Markup to
      # render any matching pages
      def register(ext, name, options = {}, &block)
        regexp = options[:regexp] || Regexp.new(ext.to_s)
        @formats[ext] = { :name => name, :regexp => regexp }
        GitHub::Markup.add_markup(regexp, &block) if block_given?
      end
    end

    attr_accessor :toc
    attr_accessor :metadata
    attr_reader   :encoding
    attr_reader   :sanitize
    attr_reader   :format
    attr_reader   :wiki
    attr_reader   :name
    attr_reader   :include_levels
    attr_reader   :to_xml_opts

    # Initialize a new Markup object.
    #
    # page - The Gollum::Page.
    #
    # Returns a new Gollum::Markup object, ready for rendering.
    def initialize(page)
      @wiki    = page.wiki
      @name    = page.filename
      @data    = page.text_data
      @version = page.version.id if page.version
      @format  = page.format
      @sub_page = page.sub_page
      @parent_page = page.parent_page
      @dir     = ::File.dirname(page.path)
      @metadata = nil
      @to_xml_opts = { :save_with => Nokogiri::XML::Node::SaveOptions::DEFAULT_XHTML ^ 1, :indent => 0, :encoding => 'UTF-8' }
    end

    # Render the content with Gollum wiki syntax on top of the file's own
    # markup language.
    #
    # no_follow - Boolean that determines if rel="nofollow" is added to all
    #             <a> tags.
    # encoding  - Encoding Constant or String.
    #
    # Returns the formatted String content.
    def render(no_follow = false, encoding = nil, include_levels = 10)
      @sanitize = no_follow ?
        @wiki.history_sanitizer :
        @wiki.sanitizer

      @encoding = encoding
      @include_levels = include_levels

      data = @data.dup
      filter_chain = @wiki.filter_chain.map do |r|
        Gollum::Filter.const_get(r).new(self)
      end

      # Since the last 'extract' action in our chain *should* be the markup
      # to HTML converter, we now have HTML which we can parse and yield, for
      # anyone who wants it
      if block_given?
        yield Nokogiri::HTML::DocumentFragment.parse(data)
      end

      # First we extract the data through the chain...
      filter_chain.each do |filter|
        data = filter.extract(data)
      end
      
      # Then we process the data through the chain *backwards*
      filter_chain.reverse.each do |filter|
        data = filter.process(data)
      end

      # Finally, a little bit of cleanup, just because
      data.gsub!(/<p><\/p>/) do
        ''
      end

      data
    end

    # Find the given file in the repo.
    #
    # name - The String absolute or relative path of the file.
    #
    # Returns the Gollum::File or nil if none was found.
    def find_file(name, version=@version)
      if name =~ /^\//
        @wiki.file(name[1..-1], version)
      else
        path = @dir == '.' ? name : ::File.join(@dir, name)
        @wiki.file(path, version)
      end
    end

    # Hook for getting the formatted value of extracted tag data.
    #
    # type - Symbol value identifying what type of data is being extracted.
    # id   - String SHA1 hash of original extracted tag data.
    #
    # Returns the String cached formatted data, or nil.
    def check_cache(type, id)
    end

    # Hook for caching the formatted value of extracted tag data.
    #
    # type - Symbol value identifying what type of data is being extracted.
    # id   - String SHA1 hash of original extracted tag data.
    # data - The String formatted value to be cached.
    #
    # Returns nothing.
    def update_cache(type, id, data)
    end
  end

  MarkupGFM = Markup
end
