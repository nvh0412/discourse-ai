# frozen_string_literal: true

RSpec.describe DiscourseAi::Admin::AiPersonasController do
  fab!(:admin)
  fab!(:ai_persona)

  before do
    sign_in(admin)

    SiteSetting.ai_embeddings_enabled = true
    SiteSetting.ai_embeddings_discourse_service_api_endpoint = "http://test.com"
  end

  describe "GET #index" do
    it "returns a success response" do
      get "/admin/plugins/discourse-ai/ai-personas.json"
      expect(response).to be_successful

      expect(response.parsed_body["ai_personas"].length).to eq(AiPersona.count)
      expect(response.parsed_body["meta"]["tools"].length).to eq(
        DiscourseAi::AiBot::Personas::Persona.all_available_tools.length,
      )
    end

    it "sideloads llms" do
      get "/admin/plugins/discourse-ai/ai-personas.json"
      expect(response).to be_successful

      expect(response.parsed_body["meta"]["llms"]).to eq(
        DiscourseAi::Configuration::LlmEnumerator.values.map do |hash|
          { "id" => hash[:value], "name" => hash[:name] }
        end,
      )
    end

    it "returns tool options with each tool" do
      persona1 = Fabricate(:ai_persona, name: "search1", tools: ["SearchCommand"])
      persona2 =
        Fabricate(
          :ai_persona,
          name: "search2",
          tools: [["SearchCommand", { base_query: "test" }, true]],
          allow_topic_mentions: true,
          allow_personal_messages: true,
          allow_chat_channel_mentions: true,
          allow_chat_direct_messages: true,
          default_llm: "anthropic:claude-2",
          forced_tool_count: 2,
        )
      persona2.create_user!

      get "/admin/plugins/discourse-ai/ai-personas.json"
      expect(response).to be_successful

      serializer_persona1 = response.parsed_body["ai_personas"].find { |p| p["id"] == persona1.id }
      serializer_persona2 = response.parsed_body["ai_personas"].find { |p| p["id"] == persona2.id }

      expect(serializer_persona2["allow_topic_mentions"]).to eq(true)
      expect(serializer_persona2["allow_personal_messages"]).to eq(true)
      expect(serializer_persona2["allow_chat_channel_mentions"]).to eq(true)
      expect(serializer_persona2["allow_chat_direct_messages"]).to eq(true)

      expect(serializer_persona2["default_llm"]).to eq("anthropic:claude-2")
      expect(serializer_persona2["user_id"]).to eq(persona2.user_id)
      expect(serializer_persona2["user"]["id"]).to eq(persona2.user_id)
      expect(serializer_persona2["forced_tool_count"]).to eq(2)

      tools = response.parsed_body["meta"]["tools"]
      search_tool = tools.find { |c| c["id"] == "Search" }

      expect(search_tool["help"]).to eq(I18n.t("discourse_ai.ai_bot.tool_help.search"))

      expect(search_tool["options"]).to eq(
        {
          "base_query" => {
            "type" => "string",
            "name" => I18n.t("discourse_ai.ai_bot.tool_options.search.base_query.name"),
            "description" =>
              I18n.t("discourse_ai.ai_bot.tool_options.search.base_query.description"),
          },
          "max_results" => {
            "type" => "integer",
            "name" => I18n.t("discourse_ai.ai_bot.tool_options.search.max_results.name"),
            "description" =>
              I18n.t("discourse_ai.ai_bot.tool_options.search.max_results.description"),
          },
          "search_private" => {
            "type" => "boolean",
            "name" => I18n.t("discourse_ai.ai_bot.tool_options.search.search_private.name"),
            "description" =>
              I18n.t("discourse_ai.ai_bot.tool_options.search.search_private.description"),
          },
        },
      )

      expect(serializer_persona1["tools"]).to eq(["SearchCommand"])
      expect(serializer_persona2["tools"]).to eq(
        [["SearchCommand", { "base_query" => "test" }, true]],
      )
    end

    context "with translations" do
      before do
        SiteSetting.default_locale = "fr"

        TranslationOverride.upsert!(
          SiteSetting.default_locale,
          "discourse_ai.ai_bot.personas.general.name",
          "Général",
        )
        TranslationOverride.upsert!(
          SiteSetting.default_locale,
          "discourse_ai.ai_bot.personas.general.description",
          "Général Description",
        )
      end

      after do
        TranslationOverride.revert!(
          SiteSetting.default_locale,
          "discourse_ai.ai_bot.personas.general.name",
        )
        TranslationOverride.revert!(
          SiteSetting.default_locale,
          "discourse_ai.ai_bot.personas.general.description",
        )
      end

      it "returns localized persona names and descriptions" do
        get "/admin/plugins/discourse-ai/ai-personas.json"

        id =
          DiscourseAi::AiBot::Personas::Persona.system_personas[
            DiscourseAi::AiBot::Personas::General
          ]
        persona = response.parsed_body["ai_personas"].find { |p| p["id"] == id }

        expect(persona["name"]).to eq("Général")
        expect(persona["description"]).to eq("Général Description")
      end
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      get "/admin/plugins/discourse-ai/ai-personas/#{ai_persona.id}.json"
      expect(response).to be_successful
      expect(response.parsed_body["ai_persona"]["name"]).to eq(ai_persona.name)
    end

    it "includes rag uploads for each persona" do
      upload = Fabricate(:upload)
      RagDocumentFragment.link_target_and_uploads(ai_persona, [upload.id])

      get "/admin/plugins/discourse-ai/ai-personas/#{ai_persona.id}.json"
      expect(response).to be_successful

      serialized_persona = response.parsed_body["ai_persona"]

      expect(serialized_persona.dig("rag_uploads", 0, "id")).to eq(upload.id)
      expect(serialized_persona.dig("rag_uploads", 0, "original_filename")).to eq(
        upload.original_filename,
      )
    end
  end

  describe "POST #create" do
    context "with valid params" do
      let(:valid_attributes) do
        {
          name: "superbot",
          description: "Assists with tasks",
          system_prompt: "you are a helpful bot",
          tools: [["search", { "base_query" => "test" }, true]],
          top_p: 0.1,
          temperature: 0.5,
          allow_topic_mentions: true,
          allow_personal_messages: true,
          allow_chat_channel_mentions: true,
          allow_chat_direct_messages: true,
          default_llm: "anthropic:claude-2",
          forced_tool_count: 2,
        }
      end

      it "creates a new AiPersona" do
        expect {
          post "/admin/plugins/discourse-ai/ai-personas.json",
               params: { ai_persona: valid_attributes }.to_json,
               headers: {
                 "CONTENT_TYPE" => "application/json",
               }
          expect(response).to be_successful
          persona_json = response.parsed_body["ai_persona"]

          expect(persona_json["name"]).to eq("superbot")
          expect(persona_json["top_p"]).to eq(0.1)
          expect(persona_json["temperature"]).to eq(0.5)
          expect(persona_json["default_llm"]).to eq("anthropic:claude-2")
          expect(persona_json["forced_tool_count"]).to eq(2)
          expect(persona_json["allow_topic_mentions"]).to eq(true)
          expect(persona_json["allow_personal_messages"]).to eq(true)
          expect(persona_json["allow_chat_channel_mentions"]).to eq(true)
          expect(persona_json["allow_chat_direct_messages"]).to eq(true)

          persona = AiPersona.find(persona_json["id"])

          expect(persona.tools).to eq([["search", { "base_query" => "test" }, true]])
          expect(persona.top_p).to eq(0.1)
          expect(persona.temperature).to eq(0.5)
        }.to change(AiPersona, :count).by(1)
      end
    end

    context "with invalid params" do
      it "renders a JSON response with errors for the new ai_persona" do
        post "/admin/plugins/discourse-ai/ai-personas.json", params: { ai_persona: { foo: "" } } # invalid attribute
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.content_type).to include("application/json")
      end
    end
  end

  describe "POST #create_user" do
    it "creates a user for the persona" do
      post "/admin/plugins/discourse-ai/ai-personas/#{ai_persona.id}/create-user.json"
      ai_persona.reload

      expect(response).to be_successful
      expect(response.parsed_body["user"]["id"]).to eq(ai_persona.user_id)
    end
  end

  describe "PUT #update" do
    it "allows us to trivially clear top_p and temperature" do
      persona = Fabricate(:ai_persona, name: "test_bot2", top_p: 0.5, temperature: 0.1)
      put "/admin/plugins/discourse-ai/ai-personas/#{persona.id}.json",
          params: {
            ai_persona: {
              top_p: "",
              temperature: "",
            },
          }

      expect(response).to have_http_status(:ok)
      persona.reload

      expect(persona.top_p).to eq(nil)
      expect(persona.temperature).to eq(nil)
    end

    it "supports updating rag params" do
      persona = Fabricate(:ai_persona, name: "test_bot2")

      put "/admin/plugins/discourse-ai/ai-personas/#{persona.id}.json",
          params: {
            ai_persona: {
              rag_chunk_tokens: "102",
              rag_chunk_overlap_tokens: "12",
              rag_conversation_chunks: "13",
            },
          }

      expect(response).to have_http_status(:ok)
      persona.reload

      expect(persona.rag_chunk_tokens).to eq(102)
      expect(persona.rag_chunk_overlap_tokens).to eq(12)
      expect(persona.rag_conversation_chunks).to eq(13)
    end

    it "supports updating vision params" do
      persona = Fabricate(:ai_persona, name: "test_bot2")
      put "/admin/plugins/discourse-ai/ai-personas/#{persona.id}.json",
          params: {
            ai_persona: {
              vision_enabled: true,
              vision_max_pixels: 512 * 512,
            },
          }

      expect(response).to have_http_status(:ok)
      persona.reload

      expect(persona.vision_enabled).to eq(true)
      expect(persona.vision_max_pixels).to eq(512 * 512)
    end

    it "does not allow temperature and top p changes on stock personas" do
      put "/admin/plugins/discourse-ai/ai-personas/#{DiscourseAi::AiBot::Personas::Persona.system_personas.values.first}.json",
          params: {
            ai_persona: {
              top_p: 0.5,
              temperature: 0.1,
            },
          }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    context "with valid params" do
      it "updates the requested ai_persona" do
        put "/admin/plugins/discourse-ai/ai-personas/#{ai_persona.id}.json",
            params: {
              ai_persona: {
                name: "SuperBot",
                enabled: false,
                tools: ["search"],
              },
            }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")

        ai_persona.reload
        expect(ai_persona.name).to eq("SuperBot")
        expect(ai_persona.enabled).to eq(false)
        expect(ai_persona.tools).to eq([["search", nil, false]])
      end
    end

    context "with system personas" do
      it "does not allow editing of system prompts" do
        put "/admin/plugins/discourse-ai/ai-personas/#{DiscourseAi::AiBot::Personas::Persona.system_personas.values.first}.json",
            params: {
              ai_persona: {
                system_prompt: "you are not a helpful bot",
              },
            }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["errors"].join).not_to be_blank
        expect(response.parsed_body["errors"].join).not_to include("en.discourse")
      end

      it "does not allow editing of tools" do
        put "/admin/plugins/discourse-ai/ai-personas/#{DiscourseAi::AiBot::Personas::Persona.system_personas.values.first}.json",
            params: {
              ai_persona: {
                tools: %w[SearchCommand ImageCommand],
              },
            }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["errors"].join).not_to be_blank
        expect(response.parsed_body["errors"].join).not_to include("en.discourse")
      end

      it "does not allow editing of name and description cause it is localized" do
        put "/admin/plugins/discourse-ai/ai-personas/#{DiscourseAi::AiBot::Personas::Persona.system_personas.values.first}.json",
            params: {
              ai_persona: {
                name: "bob",
                description: "the bob",
              },
            }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["errors"].join).not_to be_blank
        expect(response.parsed_body["errors"].join).not_to include("en.discourse")
      end

      it "does allow some actions" do
        put "/admin/plugins/discourse-ai/ai-personas/#{DiscourseAi::AiBot::Personas::Persona.system_personas.values.first}.json",
            params: {
              ai_persona: {
                allowed_group_ids: [Group::AUTO_GROUPS[:trust_level_1]],
                enabled: false,
                priority: 989,
              },
            }

        expect(response).to be_successful
      end
    end

    context "with invalid params" do
      it "renders a JSON response with errors for the ai_persona" do
        put "/admin/plugins/discourse-ai/ai-personas/#{ai_persona.id}.json",
            params: {
              ai_persona: {
                name: "",
              },
            } # invalid attribute
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.content_type).to include("application/json")
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested ai_persona" do
      expect {
        delete "/admin/plugins/discourse-ai/ai-personas/#{ai_persona.id}.json"

        expect(response).to have_http_status(:no_content)
      }.to change(AiPersona, :count).by(-1)
    end

    it "is not allowed to delete system personas" do
      expect {
        delete "/admin/plugins/discourse-ai/ai-personas/#{DiscourseAi::AiBot::Personas::Persona.system_personas.values.first}.json"
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["errors"].join).not_to be_blank
        # let's make sure this is translated
        expect(response.parsed_body["errors"].join).not_to include("en.discourse")
      }.not_to change(AiPersona, :count)
    end
  end
end
