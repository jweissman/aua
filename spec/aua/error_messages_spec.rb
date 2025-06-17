RSpec.describe "Parser and Lexer Error Messages" do
  describe "lexer errors" do
    it "provides clear position information for unexpected tokens" do
      code = <<~AUA
        x = 42
        y = @invalid_token
        z = 100
      AUA
      
      expect { Aua.run(code) }.to raise_error do |error|
        expect(error.message).to include("line 2")
        expect(error.message).to include("@invalid_token")
        # Should show context around the error
        expect(error.message).to include("y = @invalid_token")
      end
    end

    it "provides position information for unterminated strings" do
      code = <<~AUA
        x = "unterminated string
        y = 42
      AUA
      
      expect { Aua.run(code) }.to raise_error do |error|
        expect(error.message).to include("line 1")
        expect(error.message).to include("unterminated")
      end
    end
  end

  describe "parser errors" do
    it "provides clear position information for syntax errors" do
      code = <<~AUA
        x = 42
        y = ( 1 + 2
        z = 100
      AUA
      
      expect { Aua.run(code) }.to raise_error do |error|
        expect(error.message).to include("line 2")
        expect(error.message).to include("unmatched")
        # Should show context with caret position
        expect(error.message).to include("y = ( 1 + 2")
        expect(error.message).to match(/\^/)
      end
    end

    it "provides position information for unexpected tokens in type definitions" do
      code = <<~AUA
        type Point = { x: Int y: Int }
        result = { x: 1, y: 2 }
      AUA
      
      expect { Aua.run(code) }.to raise_error do |error|
        expect(error.message).to include("line 1")
        expect(error.message).to include("expected")
        expect(error.message).to include("type Point = { x: Int y: Int }")
      end
    end
  end

  describe "multi-line error context" do
    it "shows context across multiple lines for complex errors" do
      code = <<~AUA
        type Person = {
          name: Str,
          age: Int
          email: Str
        }
        
        person = {
          name: "John",
          age: invalid_expression,
          email: "john@example.com"
        }
      AUA
      
      expect { Aua.run(code) }.to raise_error do |error|
        expect(error.message).to include("line 9")
        expect(error.message).to include("invalid_expression")
        # Should show surrounding context
        expect(error.message).to include("age: invalid_expression")
      end
    end
  end
end
