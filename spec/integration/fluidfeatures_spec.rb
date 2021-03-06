require "spec_helper"

describe "FluidFeatures" do

  describe "App initialization" do
    it "should raise 'host not set' without valid base uri" do
      expect { FluidFeatures.app(config.remove("baseuri")) }.
        to raise_error(StandardError, /host not set/)
    end

    it "should raise 'app_id invalid' without valid app id" do
      expect { FluidFeatures.app(config.remove("appid")) }.
        to raise_error(StandardError, /app_id invalid/)
    end

    it "should raise 'secret invalid' without valid secret" do
      expect { FluidFeatures.app(config.remove("secret")) }.
          to raise_error(StandardError, /secret invalid/)
    end

    it "should set @config class variable to passed config" do
      FluidFeatures::Client.stub!(:new); FluidFeatures::App.stub!(:new)
      config = mock("config", "[]" => nil, "[]=" => nil)
      FluidFeatures.app(config)
      FluidFeatures.config.should == config
    end
  end

  describe "API methods" do
    #let(:feature_name) { "Feature-#{UUID.new.generate}" }
    let(:feature_name) { "Feature1" }

    let(:feature) { app.features.pop[feature_name] }

    specify "#feature_enabled? should create feature" do
      VCR.use_cassette('feature') do
        transaction.feature_enabled?(feature_name, "a", true)
        transaction.feature_enabled?(feature_name, "b", true)
        commit transaction
        sleep abit
        feature["name"].should == feature_name
        feature["versions"].size.should == 2
      end
    end

    specify "#goal_hit should create goal" do
      VCR.use_cassette('goal') do
        transaction.feature_enabled?(feature_name, "a", true)
        transaction.goal_hit("Goal", "a")
        commit transaction
        sleep abit
      end
    end
  end
end
