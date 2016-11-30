module Xcflushd

  # Credentials contains all the fields required to authenticate an app.
  # In 3scale there are 3 authentication modes:
  #   * App ID: app_id (required), app_key, referrer, user_id
  #   * API key: user_key (required), referrer, user_id
  #   * Oauth: access_token (required), app_id, referrer, user_id
  class Credentials

    FIELDS = [:app_id, :app_key, :referrer, :user_id, :user_key, :access_token].freeze
    private_constant :FIELDS

    attr_reader :creds

    # Initializes a credentials object from a 'creds' hash.
    # The accepted fields of the hash are:
    #   app_id, app_key, referrer, user_id, user_key, and access_token.
    # Extra fields are discarded.
    def initialize(creds)
      @creds = creds.select { |k, _| FIELDS.include?(k) }
    end

    # This method returns all the credentials with this format:
    # credential1:value1,credential2:value2, etc.
    # The delimiters used, ',' and ':', are escaped in the values. Also, the
    # credentials appear in alphabetical order.
    def to_sorted_escaped_s
      creds.sort_by { |cred, _| cred }
           .map { |cred, value| "#{escaped(cred.to_s)}:#{escaped(value)}" }
           .join(',')
    end

    def ==(other)
      self.class == other.class && creds == other.creds
    end

    def oauth?
      !creds[:access_token].nil?
    end

    # Creates a Credentials object from an escaped string. The string has this
    # format: credential1:value1,credential2:value2, etc. ',' and ':' are
    # escaped in the values
    def self.from(escaped_s)
      creds_hash = escaped_s.split(/(?<!\\),/)
                            .map { |field_value| field_value.split(/(?<!\\):/) }
                            .map { |split| [unescaped(split[0]).to_sym,
                                            unescaped(split[1])] }
                            .to_h

      new(creds_hash)
    end

    private

    def escaped(string)
      string.gsub(','.freeze, "\\,".freeze)
            .gsub(':'.freeze, "\\:".freeze)
    end

    def self.unescaped(string)
      string.gsub(/\\([,:])/, '\1')
    end

  end
end
