# frozen_string_literal: true

RSpec.describe Jobs::EmbeddingsBackfill do
  fab!(:second_topic) do
    topic = Fabricate(:topic, created_at: 1.year.ago, bumped_at: 2.day.ago)
    Fabricate(:post, topic: topic)
    topic
  end

  fab!(:first_topic) do
    topic = Fabricate(:topic, created_at: 1.year.ago, bumped_at: 1.day.ago)
    Fabricate(:post, topic: topic)
    topic
  end

  fab!(:third_topic) do
    topic = Fabricate(:topic, created_at: 1.year.ago, bumped_at: 3.day.ago)
    Fabricate(:post, topic: topic)
    topic
  end

  let(:vector_rep) do
    strategy = DiscourseAi::Embeddings::Strategies::Truncation.new
    DiscourseAi::Embeddings::VectorRepresentations::Base.current_representation(strategy)
  end

  before do
    SiteSetting.ai_embeddings_enabled = true
    SiteSetting.ai_embeddings_discourse_service_api_endpoint = "http://test.com"
    SiteSetting.ai_embeddings_backfill_batch_size = 1
    Jobs.run_immediately!
  end

  it "backfills topics based on bumped_at date" do
    embedding = Array.new(1024) { 1 }

    WebMock.stub_request(
      :post,
      "#{SiteSetting.ai_embeddings_discourse_service_api_endpoint}/api/v1/classify",
    ).to_return(status: 200, body: JSON.dump(embedding))

    Jobs::EmbeddingsBackfill.new.execute({})

    topic_ids = DB.query_single("SELECT topic_id from #{vector_rep.topic_table_name}")

    expect(topic_ids).to eq([first_topic.id])

    # pulse again for the rest (and cover code)
    SiteSetting.ai_embeddings_backfill_batch_size = 100
    Jobs::EmbeddingsBackfill.new.execute({})

    topic_ids = DB.query_single("SELECT topic_id from #{vector_rep.topic_table_name}")

    expect(topic_ids).to contain_exactly(first_topic.id, second_topic.id, third_topic.id)

    freeze_time 1.day.from_now

    # new title forces a reindex
    third_topic.update!(updated_at: Time.zone.now, title: "new title - 123")

    Jobs::EmbeddingsBackfill.new.execute({})

    index_date =
      DB.query_single(
        "SELECT updated_at from #{vector_rep.topic_table_name} WHERE topic_id = ?",
        third_topic.id,
      ).first

    expect(index_date).to be_within_one_second_of(Time.zone.now)
  end
end
