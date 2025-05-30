# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aua do
  it "has a version number" do
    expect(Aua::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(Aua.run("123").value).to eq(123)
  end

  it "returns an Int object for integer literals" do
    result = Aua.run("123")
    expect(result).to be_a(Aua::Int)
    expect(result.value).to eq(123)
  end

  it "recognizes negative integers" do
    result = Aua.run("-42")
    expect(result).to be_a(Aua::Int)
    expect(result.value).to eq(-42)
  end

  it "recognizes floating point literals" do
    result = Aua.run("3.14")
    expect(result).to be_a(Aua::Float)
    expect(result.value).to eq(3.14)
  end

  it "recognizes boolean true literal" do
    result = Aua.run("true")
    expect(result).to be_a(Aua::Bool)
    expect(result.value).to eq(true)
  end

  it "recognizes boolean false literal" do
    result = Aua.run("false")
    expect(result).to be_a(Aua::Bool)
    expect(result.value).to eq(false)
  end

  it "recognizes string literals" do
    result = Aua.run('"hello"')
    expect(result).to be_a(Aua::Str)
    expect(result.value).to eq("hello")
  end

  it "recognizes nil literal" do
    result = Aua.run("nihil")
    expect(result).to be_a(Aua::Nihil)
    expect(result.value).to be_nil
  end

  it "recognizes boolean literal" do
    result = Aua.run("true")
    expect(result).to be_a(Aua::Bool)
    expect(result.value).to eq(true)

    result = Aua.run("false")
    expect(result).to be_a(Aua::Bool)
    expect(result.value).to eq(false)
  end

  it "raises an error for parsing problems" do
    expect { Aua.run("123abc") }.to raise_error(Aua::Error)
  end

  it "recognizes parenthesized expressions" do
    result = Aua.run("(123)")
    expect(result).to be_a(Aua::Int)
    expect(result.value).to eq(123)
  end
end
