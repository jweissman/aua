require "spec_helper"

RSpec.describe "String Edge Cases" do
  describe "complex string content" do
    it "handles strings with dots" do
      expect('"hello.world"').to be_aua("hello.world")
    end

    it "handles strings with multiple dots" do
      expect('"www.example.com"').to be_aua("www.example.com")
    end

    it "handles strings with special characters" do
      expect('"hello@world#test$"').to be_aua("hello@world#test$")
    end

    it "handles strings with numbers and symbols" do
      expect('"v1.2.3-beta.1"').to be_aua("v1.2.3-beta.1")
    end

    it "handles strings with mixed alphanumeric" do
      expect('"user123@domain.co.uk"').to be_aua("user123@domain.co.uk")
    end

    it "handles strings with underscores and hyphens" do
      expect('"snake_case-kebab-case"').to be_aua("snake_case-kebab-case")
    end

    it "handles strings with parentheses" do
      expect('"func(arg1, arg2)"').to be_aua("func(arg1, arg2)")
    end

    it "handles strings with brackets" do
      expect('"array[0].property"').to be_aua("array[0].property")
    end

    it "handles strings with mathematical expressions" do
      expect('"x = y + z * (a - b)"').to be_aua("x = y + z * (a - b)")
    end

    it "handles JSON-like strings" do
      expect('"{\"key\": \"value\", \"num\": 42}"').to be_aua('{"key": "value", "num": 42}')
    end

    it "handles path-like strings" do
      expect('"/home/user/documents/file.txt"').to be_aua("/home/user/documents/file.txt")
    end

    it "handles URL-like strings" do
      expect('"https://api.example.com/v1/users?id=123&format=json"').to be_aua("https://api.example.com/v1/users?id=123&format=json")
    end
  end

  describe "string interpolation with complex content" do
    it "interpolates expressions with dots" do
      code = 'name = "user.config"; "File: ${name}"'
      expect(code).to be_aua("File: user.config")
    end

    it "interpolates complex variable names" do
      code = 'api_endpoint = "https://api.test.com"; "Connecting to ${api_endpoint}/users"'
      expect(code).to be_aua("Connecting to https://api.test.com/users")
    end
  end

  describe "strings in operations" do
    it "concatenates strings with special characters" do
      code = '"prefix." + "suffix@domain.com"'
      expect(code).to be_aua("prefix.suffix@domain.com")
    end

    it "compares strings with dots" do
      code = '"config.json" == "config.json"'
      expect(code).to be_aua(true)
    end
  end

  describe "string stress testing and repetitive operations" do
    it "handles multiple string assignments on separate lines" do
      code = <<~AUA
        first = "hello"
        second = "world"
        third = "test"
        fourth = "string"
        fifth = "parsing"
        sixth = "performance"
        seventh = "multiple"
        eighth = "assignments"
        ninth = "should"
        tenth = "work"
        tenth
      AUA

      expect(code).to be_aua("work")
    end

    it "handles complex multi-line interpolation chains" do
      code = <<~AUA
        base_url = "https://api.example.com"
        version = "v1"
        endpoint = "users"
        user_id = "12345"
        format = "json"

        api_path = "${base_url}/${version}"
        full_endpoint = "${api_path}/${endpoint}"
        user_url = "${full_endpoint}/${user_id}"
        final_url = "${user_url}?format=${format}"

        final_url
      AUA

      expect(code).to be_aua("https://api.example.com/v1/users/12345?format=json")
    end

    it "handles nested interpolation with complex expressions" do
      code = <<~AUA
        prefix = "LOG"
        timestamp = "2024-01-01"
        level = "INFO"
        component = "auth"
        message = "User login successful"

        log_header = "[${prefix}:${timestamp}]"
        log_level = "[${level}]"
        log_component = "[${component}]"
        log_message = "${message}"

        full_log = "${log_header} ${log_level} ${log_component} ${log_message}"
        final_output = "System output: ${full_log}"

        final_output
      AUA

      expect(code).to be_aua("System output: [LOG:2024-01-01] [INFO] [auth] User login successful")
    end

    it "handles repetitive string operations with special characters" do
      code = <<~AUA
        email_user = "john.doe"
        email_domain = "company.co.uk"
        email_full = "${email_user}@${email_domain}"

        path_base = "/var/log"
        path_app = "myapp"
        path_file = "access.log"
        full_path = "${path_base}/${path_app}/${path_file}"

        config_key = "database.connection.timeout"
        config_value = "30000"
        config_entry = "${config_key}=${config_value}"

        summary = "Email: ${email_full}, Path: ${full_path}, Config: ${config_entry}"
        summary
      AUA

      expect(code).to be_aua("Email: john.doe@company.co.uk, Path: /var/log/myapp/access.log, Config: database.connection.timeout=30000")
    end

    it "handles string concatenation chains with interpolation" do
      code = <<~AUA
        protocol = "https"
        subdomain = "api"
        domain = "myservice"
        tld = "com"
        port = "8443"

        base = "${protocol}://"
        host = "${subdomain}.${domain}.${tld}"
        port_part = ":${port}"

        stage1 = base + host
        stage2 = stage1 + port_part
        final = stage2 + "/health"

        final
      AUA

      expect(code).to be_aua("https://api.myservice.com:8443/health")
    end

    it "handles many sequential string assignments with dots and special chars" do
      code = <<~AUA
        config_1 = "app.database.host=localhost"
        config_2 = "app.database.port=5432"
        config_3 = "app.cache.redis.url=redis://localhost:6379"
        config_4 = "app.logging.level=INFO"
        config_5 = "app.security.jwt.secret=my-secret-key-2024"
        config_6 = "app.features.beta.enabled=true"
        config_7 = "app.monitoring.metrics.endpoint=/metrics"
        config_8 = "app.api.rate_limit.requests_per_minute=1000"

        summary = "${config_1}; ${config_2}; ${config_3}; ${config_4}"
        summary
      AUA

      expect(code).to be_aua("app.database.host=localhost; app.database.port=5432; app.cache.redis.url=redis://localhost:6379; app.logging.level=INFO")
    end

    it "handles deeply nested interpolation with performance implications" do
      code = <<~AUA
        a = "start"
        b = "${a}-level1"
        c = "${b}-level2"
        d = "${c}-level3"
        e = "${d}-level4"
        f = "${e}-level5"
        g = "${f}-level6"
        h = "${g}-level7"
        i = "${h}-level8"
        j = "${i}-level9"
        k = "${j}-end"

        k
      AUA

      expect(code).to be_aua("start-level1-level2-level3-level4-level5-level6-level7-level8-level9-end")
    end

    it "handles mixed string operations with complex content" do
      code = <<~AUA
        json_start = '{"users": ['
        user_1 = '{"id": 1, "email": "user1@example.com"}'
        user_2 = '{"id": 2, "email": "user2@test.org"}'
        user_3 = '{"id": 3, "email": "admin@company.co.uk"}'
        json_end = ']}'

        separator = ", "
        users_part = user_1 + separator + user_2 + separator + user_3
        full_json = json_start + users_part + json_end

        wrapped = "API Response: ${full_json}"
        wrapped
      AUA

      expected = 'API Response: {"users": [{"id": 1, "email": "user1@example.com"}, {"id": 2, "email": "user2@test.org"}, {"id": 3, "email": "admin@company.co.uk"}]}'
      expect(code).to be_aua(expected)
    end
  end
end
