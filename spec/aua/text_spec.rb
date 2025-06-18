# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aua::Text do
  describe Aua::Text::Cursor do
    subject(:cursor) { described_class.new(5, 10) }

    describe "#initialize" do
      it "sets column and line" do
        expect(cursor.column).to eq(5)
        expect(cursor.line).to eq(10)
      end
    end

    describe "#advance" do
      it "increments column" do
        expect { cursor.advance }.to change(cursor, :column).from(5).to(6)
      end
    end

    describe "#newline" do
      it "increments line" do
        expect { cursor.newline }.to change(cursor, :line).from(10).to(11)
      end

      it "resets column to 1" do
        expect { cursor.newline }.to change(cursor, :column).from(5).to(1)
      end
    end

    describe "#to_s" do
      it "returns formatted position string" do
        expect(cursor.to_s).to eq("at line 10, column 5")
      end
    end
  end

  describe Aua::Text::Document do
    let(:text) { "hello\nworld\ntest" }
    subject(:doc) { described_class.new(text) }

    describe "#initialize" do
      it "sets up document with text and initial position" do
        expect(doc.content).to eq(text)
        expect(doc.position).to eq(0)
        expect(doc.cursor.column).to eq(1)
        expect(doc.cursor.line).to eq(1)
      end
    end

    describe "#current" do
      it "returns current character" do
        expect(doc.current).to eq("h")
      end

      context "at end of document" do
        before { doc.instance_variable_set(:@position, text.length) }

        it "returns nil" do
          expect(doc.current).to be_nil
        end
      end
    end

    describe "#peek" do
      it "returns next character without advancing" do
        expect(doc.peek).to eq("e")
        expect(doc.current).to eq("h") # position unchanged
      end
    end

    describe "#peek_at" do
      it "returns character at relative position" do
        expect(doc.peek_at(0)).to eq("h")
        expect(doc.peek_at(1)).to eq("e")
        expect(doc.peek_at(4)).to eq("o")
      end

      it "returns nil for out-of-bounds positions" do
        expect(doc.peek_at(100)).to be_nil
      end
    end

    describe "#peek_n" do
      it "returns array of next n characters" do
        expect(doc.peek_n(3)).to eq(%w[e l l])
      end

      it "returns as many as possible if fewer than n available" do
        doc.instance_variable_set(:@position, text.length - 2)
        expect(doc.peek_n(5)).to eq(["t", "", "", "", ""])
      end

      it "returns empty array for n=0" do
        expect(doc.peek_n(0)).to eq([])
      end
    end

    describe "#advance" do
      it "advances position and cursor" do
        expect { doc.advance }.to change(doc, :position).from(0).to(1)
        expect(doc.cursor.column).to eq(2)
        expect(doc.cursor.line).to eq(1)
      end

      xit "handles newlines correctly" do
        doc.advance(5) # advance to newline
        expect(doc.current).to eq("\n")
        expect(doc.cursor.line).to eq(1)
        expect(doc.cursor.column).to eq(5)
        doc.advance(1) # advance past newline
        expect(doc.cursor.line).to eq(2)
        expect(doc.cursor.column).to eq(1)
      end

      it "can advance multiple characters" do
        doc.advance(3)
        expect(doc.position).to eq(3)
        expect(doc.current).to eq("l")
      end

      it "handles advancing past end gracefully" do
        result = doc.advance(100)
        expect(result).to be_truthy
        expect(doc.finished?).to be true
      end
    end

    describe "#finished?" do
      it "returns false when not at end" do
        expect(doc.finished?).to be false
      end

      it "returns true when at end" do
        doc.advance(text.length)
        expect(doc.finished?).to be true
      end
    end

    describe "#caret" do
      it "returns frozen copy of cursor" do
        caret = doc.caret
        expect(caret).to be_frozen
        expect(caret.column).to eq(doc.cursor.column)
        expect(caret.line).to eq(doc.cursor.line)
      end
    end

    describe "#slice" do
      it "returns substring" do
        expect(doc.slice(0, 5)).to eq("hello")
        expect(doc.slice(6, 5)).to eq("world")
      end
    end

    describe "#size and #length" do
      it "returns text length" do
        expect(doc.size).to eq(text.length)
        expect(doc.length).to eq(text.length)
      end
    end

    describe "#indicate" do
      xit "returns indication of current position" do
        doc.advance(7) # position at 'o' in 'world'
        result = doc.indicate
        expect(result).to be_an(Array)
        expect(result.join("\n")).to include("^")
      end
    end
  end

  describe ".indicate" do
    let(:code) { "let x = 5\nlet y = 10" }
    let(:cursor) { Aua::Text::Cursor.new(5, 2) }

    xit "creates indication with caret at specified position" do
      result = described_class.indicate(code, cursor)
      expect(result).to be_an(Array)

      indication = result.join("\n")
      expect(indication).to include("let x = 5")
      expect(indication).to include("let y = 10")
      expect(indication).to include("    ^") # caret at column 5
    end

    xit "handles single line code" do
      single_line = "let x = 5"
      cursor = Aua::Text::Cursor.new(7, 1)
      result = described_class.indicate(single_line, cursor)

      indication = result.join("\n")
      expect(indication).to include("let x = 5")
      expect(indication).to include("      ^") # caret at column 7
    end

    xit "handles multi-line with specific line highlighting" do
      multi_line = "line 1\nline 2\nline 3"
      cursor = Aua::Text::Cursor.new(3, 2)
      result = described_class.indicate(multi_line, cursor)

      indication = result.join("\n")
      expect(indication).to include("line 1")
      expect(indication).to include("line 2")
      expect(indication).to include("  ^") # caret at column 3 of line 2
      expect(indication).to include("line 3")
    end
  end
end
