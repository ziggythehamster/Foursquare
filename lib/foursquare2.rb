require 'rubygems'
require 'httparty'
require 'hashie'
require 'oauth2'

Hash.send :include, Hashie::HashExtensions

module Foursquare2
  class OAuth2
    # Usage:
    #   
    #   Foursquare2::OAuth.new("YOUR_APP_ID", "YOUR_APP_SECRET", "YOUR_REGISTERED_APP_REDIRECT")
    def initialize(cid, csecret, redirect_uri)
      @client_id, @client_secret, @callback_uri = cid, csecret, redirect_uri
      @client = nil
      @access_token = nil
    end

    # Initializes the client or returns the existing
    # one.
    def client
      return @client if @client
      @client = ::OAuth2::Client.new(@client_id, @client_secret, {
        :site               => "https://foursquare.com",
        :access_token_path  => "/oauth2/access_token",
        :authorize_path     => "/oauth2/authorize"
      })
    end

    # Returns the authorize URL to redirect to.
    def authorize_url
      # FIXME: Raise an error if @callback_uri isn't set.
	
      self.client.web_server.authorize_url(:redirect_uri => @callback_uri, :response_type => "code")
    end

    # Gets the access token. Pass in the code that authorize_url returned. To get the token,
    # use something like oauth.access_token.token.
    def access_token(code = nil)
      return @access_token if @access_token
      return nil if code.nil?
      @access_token = self.client.web_server.get_access_token(code, :redirect_uri => @callback_uri, :grant_type => "authorization_code")
    end

    # Sets the access token. Use this when you have a stored access token, then use
    # access_token to get the access token object. This method expects a String or
    # nil.
    def access_token=(new_access_token = nil)
      if new_access_token.nil?
        @access_token = nil
      else
        @access_token = ::OAuth2::AccessToken.new(self, new_access_token)
      end
    end
  end
  
  class Base
    BASE_URL = 'https://api.foursquare.com/v2'
    
    attr_accessor :oauth
    
    def initialize(oauth)
      @oauth = oauth
    end
    
    # Methods get used like this:
    #   .checkins_add!(:venueId => 1, :shout => "Checking in!")
    #   .users_badges(:id => 12345)
    #   .venues_herenow(:id => 1)
    #
    # Basically, take the endpoint name like checkins/add and replace / with _.
    # If you need to pass in an ID (as in venues/ID/herenow), use the :id parameter.
    #
    # POSTs end in ! - this is to indicate that the function makes changes
    def method_missing(method_symbol, params = {})
      method_name = method_symbol.to_s.split(/\.|_/).join('/')
      id = params.delete(:id)
      
      if (method_name[-1,1]) == '!'
        method = method_name[0..-2]
        result = post(api_url(method, nil, id), params)
        result[method] || result
      else
        result = get(api_url(method_name, params))
        result[method_name] || result
      end
    end
    
    def api(method_symbol, params = {})
      Hashie::Mash.new(method_missing(method_symbol, params))
    end
    
    def api_url(method_name, options = nil, id = nil)
      params = options.is_a?(Hash) ? to_query_params(options) : options
      params = nil if params and params.blank?

      method_arr = method_name.split("/")

      # Add the ID to the method array if an ID was passed in.
      method_arr.insert(1, id) if id

      url = BASE_URL + '/' + method_arr.join('/')
      url += "?#{params}" if params
      url = URI.escape(url)
      url
    end
    
    def parse_response(response)
      raise_errors(response)
      Crack::JSON.parse(response.body)
    end
    
    def to_query_params(options)
      options.collect { |key, value| "#{key}=#{value}" }.join('&')
    end
    
    def get(url)
      puts "[4sq2] GET #{url}" if $DEBUG

      if @oauth.access_token.nil?
        parse_response(@oauth.client.request(:get, url))
      else
        parse_response(@oauth.access_token.get(url))
      end
    end
    
    def post(url, body)
      puts "[4sq2] POST #{url} - #{body}" if $DEBUG

      if @oauth.access_token.nil?
        parse_response(@oauth.client.request(:post, url, body))
      else
        parse_response(@oauth.access_token.post(url, body))
      end
    end
    
    private
    
    
    def raise_errors(response)
      message = "(#{response.code}): #{response.message} - #{response.inspect} - #{response.body}"
      
      case response.code.to_i
        when 400
          raise BadRequest, message
        when 401
          raise Unauthorized, message
        when 403
          raise Forbidden, message
        when 404
          raise NotFound, message
	when 405
	  raise NotAllowed, message
        when 500
          raise InternalError, "Foursquare had an internal error. Please let them know in the group.\n#{message}"
        when 502..503
          raise Unavailable, message
      end
    end
  end
  
  
  class BadRequest        < StandardError; end
  class Unauthorized      < StandardError; end
  class Forbidden         < StandardError; end
  class Unavailable       < StandardError; end
  class InternalError     < StandardError; end
  class NotFound          < StandardError; end
  class NotAllowed        < StandardError; end
end
