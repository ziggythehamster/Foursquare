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
      @access_token = self.client.web_server.get_access_token(code, :redirect_uri => @callback_uri, :grant_type => "authorization_code")
    end

    # Clears the access token if you need it to be cleared.
    def clear_access_token!
      @access_token = nil
    end
  end
  
  class Base
    BASE_URL = 'http://api.foursquare.com/v2'
    
    attr_accessor :oauth
    
    def initialize(oauth)
      @oauth = oauth
    end
    
    #
    # Foursquare API: http://groups.google.com/group/foursquare-api/web/api-documentation
    #
    # .test                                          # api test method
    #  => {'response': 'ok'}
    # .checkin = {:shout => 'At home. Writing code'} # post new check in
    #  => {...checkin hash...}
    # .history                                       # authenticated user's checkin history
    # => [{...checkin hashie...}, {...another checkin hashie...}]
    # .send('venue.flagclosed=', {:vid => 12345})     # flag venue 12345 as closed
    # => {'response': 'ok'}
    # .venue_flagclosed = {:vid => 12345}
    # => {'response': 'ok'}
    #
    # Assignment methods(POSTs) always return a hash. Annoyingly Ruby always returns what's on
    # the right side of the assignment operator. So there are some wrapper methods below
    # for POSTs that make sure it gets turned into a hashie
    #
    def method_missing(method_symbol, params = {})
      method_name = method_symbol.to_s.split(/\.|_/).join('/')
      
      if (method_name[-1,1]) == '='
        method = method_name[0..-2]
        result = post(api_url(method), params)
        params.replace(result[method] || result)
      else
        result = get(api_url(method_name, params))
        result[method_name] || result
      end
    end
    
    def api(method_symbol, params = {})
      Hashie::Mash.new(method_missing(method_symbol, params))
    end
    
    def api_url(method_name, options = nil)
      params = options.is_a?(Hash) ? to_query_params(options) : options
      params = nil if params and params.blank?
      url = BASE_URL + '/' + method_name.split('.').join('/')
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
      parse_response(@oauth.access_token.get(url))
    end
    
    def post(url, body)
      parse_response(@oauth.access_token.post(url, body))
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
          raise General, message
        when 404
          raise NotFound, message
        when 500
          raise InternalError, "Foursquare had an internal error. Please let them know in the group.\n#{message}"
        when 502..503
          raise Unavailable, message
      end
    end
  end
  
  
  class BadRequest < StandardError; end
  class Unauthorized      < StandardError; end
  class General           < StandardError; end
  class Unavailable       < StandardError; end
  class InternalError     < StandardError; end
  class NotFound          < StandardError; end
end
