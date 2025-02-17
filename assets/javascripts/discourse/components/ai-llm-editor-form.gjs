import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input } from "@ember/component";
import { concat, get, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action, computed } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { later } from "@ember/runloop";
import { service } from "@ember/service";
import { eq } from "truth-helpers";
import DButton from "discourse/components/d-button";
import Avatar from "discourse/helpers/bound-avatar-template";
import { popupAjaxError } from "discourse/lib/ajax-error";
import icon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";
import AdminUser from "admin/models/admin-user";
import ComboBox from "select-kit/components/combo-box";
import DTooltip from "float-kit/components/d-tooltip";
import AiLlmQuotaEditor from "./ai-llm-quota-editor";
import AiLlmQuotaModal from "./modal/ai-llm-quota-modal";

export default class AiLlmEditorForm extends Component {
  @service toasts;
  @service router;
  @service dialog;

  @tracked isSaving = false;

  @tracked testRunning = false;
  @tracked testResult = null;
  @tracked testError = null;
  @tracked apiKeySecret = true;
  @tracked quotaCount = 0;

  @tracked modalIsVisible = false;

  constructor() {
    super(...arguments);
    this.updateQuotaCount();
  }

  get selectedProviders() {
    const t = (provName) => {
      return i18n(`discourse_ai.llms.providers.${provName}`);
    };

    return this.args.llms.resultSetMeta.providers.map((prov) => {
      return { id: prov, name: t(prov) };
    });
  }

  get adminUser() {
    return AdminUser.create(this.args.model?.user);
  }

  get testErrorMessage() {
    return i18n("discourse_ai.llms.tests.failure", { error: this.testError });
  }

  get displayTestResult() {
    return this.testRunning || this.testResult !== null;
  }

  @computed("args.model.provider")
  get canEditURL() {
    return this.args.model.provider !== "aws_bedrock";
  }

  get modulesUsingModel() {
    const usedBy = this.args.model.used_by?.filter((m) => m.type !== "ai_bot");

    if (!usedBy || usedBy.length === 0) {
      return null;
    }

    const localized = usedBy.map((m) => {
      return i18n(`discourse_ai.llms.usage.${m.type}`, {
        persona: m.name,
      });
    });

    // TODO: this is not perfectly localized
    return localized.join(", ");
  }

  get seeded() {
    return this.args.model.id < 0;
  }

  get inUseWarning() {
    return i18n("discourse_ai.llms.in_use_warning", {
      settings: this.modulesUsingModel,
      count: this.args.model.used_by.length,
    });
  }

  get showQuotas() {
    return this.quotaCount > 0;
  }

  get showAddQuotaButton() {
    return !this.showQuotas && !this.args.model.isNew;
  }

  @action
  updateQuotaCount() {
    this.quotaCount = this.args.model?.llm_quotas?.length || 0;
  }

  @action
  openAddQuotaModal() {
    this.modalIsVisible = true;
  }

  @computed("args.model.provider")
  get metaProviderParams() {
    const params =
      this.args.llms.resultSetMeta.provider_params[this.args.model.provider] ||
      {};

    return Object.entries(params).map(([field, value]) => {
      if (typeof value === "string") {
        return { field, type: value };
      } else if (typeof value === "object") {
        if (value.values) {
          value = { ...value };
          value.values = value.values.map((v) => {
            return { id: v, name: v };
          });
        }
        this.args.model.provider_params[field] =
          this.args.model.provider_params[field] || value.default;
        return { field, ...value };
      }
      return { field, type: "text" }; // fallback
    });
  }

  @action
  async save() {
    this.isSaving = true;
    const isNew = this.args.model.isNew;

    try {
      await this.args.model.save();

      if (isNew) {
        this.args.llms.addObject(this.args.model);
        this.router.transitionTo("adminPlugins.show.discourse-ai-llms.index");
      } else {
        this.toasts.success({
          data: { message: i18n("discourse_ai.llms.saved") },
          duration: 2000,
        });
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      later(() => {
        this.isSaving = false;
      }, 1000);
    }
  }

  @action
  async test() {
    this.testRunning = true;

    try {
      const configTestResult = await this.args.model.testConfig();
      this.testResult = configTestResult.success;

      if (this.testResult) {
        this.testError = null;
      } else {
        this.testError = configTestResult.error;
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      later(() => {
        this.testRunning = false;
      }, 1000);
    }
  }

  @action
  makeApiKeySecret() {
    this.apiKeySecret = true;
  }

  @action
  toggleApiKeySecret() {
    this.apiKeySecret = !this.apiKeySecret;
  }

  @action
  delete() {
    return this.dialog.confirm({
      message: i18n("discourse_ai.llms.confirm_delete"),
      didConfirm: () => {
        return this.args.model
          .destroyRecord()
          .then(() => {
            this.args.llms.removeObject(this.args.model);
            this.router.transitionTo(
              "adminPlugins.show.discourse-ai-llms.index"
            );
          })
          .catch(popupAjaxError);
      },
    });
  }

  @action
  closeAddQuotaModal() {
    this.modalIsVisible = false;
    this.updateQuotaCount();
  }

  <template>
    {{#if this.seeded}}
      <div class="alert alert-info">
        {{icon "circle-exclamation"}}
        {{i18n "discourse_ai.llms.seeded_warning"}}
      </div>
    {{/if}}
    {{#if this.modulesUsingModel}}
      <div class="alert alert-info">
        {{icon "circle-exclamation"}}
        {{this.inUseWarning}}
      </div>
    {{/if}}
    <form class="form-horizontal ai-llm-editor {{if this.seeded 'seeded'}}">
      <div class="control-group">
        <label>{{i18n "discourse_ai.llms.display_name"}}</label>
        <Input
          class="ai-llm-editor-input ai-llm-editor__display-name"
          @type="text"
          @value={{@model.display_name}}
          disabled={{this.seeded}}
        />
      </div>
      <div class="control-group">
        <label>{{i18n "discourse_ai.llms.name"}}</label>
        <Input
          class="ai-llm-editor-input ai-llm-editor__name"
          @type="text"
          @value={{@model.name}}
          disabled={{this.seeded}}
        />
        <DTooltip
          @icon="circle-question"
          @content={{i18n "discourse_ai.llms.hints.name"}}
        />
      </div>
      <div class="control-group">
        <label>{{i18n "discourse_ai.llms.provider"}}</label>
        <ComboBox
          @value={{@model.provider}}
          @content={{this.selectedProviders}}
          @class="ai-llm-editor__provider"
          @options={{hash disabled=this.seeded}}
        />
      </div>
      {{#unless this.seeded}}
        {{#if this.canEditURL}}
          <div class="control-group">
            <label>{{i18n "discourse_ai.llms.url"}}</label>
            <Input
              class="ai-llm-editor-input ai-llm-editor__url"
              @type="text"
              @value={{@model.url}}
              required="true"
            />
          </div>
        {{/if}}
        <div class="control-group">
          <label>{{i18n "discourse_ai.llms.api_key"}}</label>
          <div class="ai-llm-editor__secret-api-key-group">
            <Input
              @value={{@model.api_key}}
              class="ai-llm-editor-input ai-llm-editor__api-key"
              @type={{if this.apiKeySecret "password" "text"}}
              required="true"
              {{on "focusout" this.makeApiKeySecret}}
            />
            <DButton
              @action={{this.toggleApiKeySecret}}
              @icon="far-eye-slash"
            />
          </div>
        </div>
        {{#each this.metaProviderParams as |param|}}
          <div
            class="control-group ai-llm-editor-provider-param__{{param.type}}"
          >
            <label>{{i18n
                (concat "discourse_ai.llms.provider_fields." param.field)
              }}</label>
            {{#if (eq param.type "enum")}}
              <ComboBox
                @value={{mut (get @model.provider_params param.field)}}
                @content={{param.values}}
              />
            {{else if (eq param.type "checkbox")}}
              <Input
                @type={{param.type}}
                @checked={{mut (get @model.provider_params param.field)}}
              />
            {{else}}
              <Input
                @type={{param.type}}
                @value={{mut (get @model.provider_params param.field)}}
              />
            {{/if}}
          </div>
        {{/each}}
        <div class="control-group">
          <label>{{i18n "discourse_ai.llms.tokenizer"}}</label>
          <ComboBox
            @value={{@model.tokenizer}}
            @content={{@llms.resultSetMeta.tokenizers}}
            @class="ai-llm-editor__tokenizer"
          />
        </div>
        <div class="control-group">
          <label>{{i18n "discourse_ai.llms.max_prompt_tokens"}}</label>
          <Input
            @type="number"
            class="ai-llm-editor-input ai-llm-editor__max-prompt-tokens"
            step="any"
            min="0"
            lang="en"
            @value={{@model.max_prompt_tokens}}
            required="true"
          />
          <DTooltip
            @icon="circle-question"
            @content={{i18n "discourse_ai.llms.hints.max_prompt_tokens"}}
          />
        </div>
        <div class="control-group ai-llm-editor__vision-enabled">
          <Input @type="checkbox" @checked={{@model.vision_enabled}} />
          <label>{{i18n "discourse_ai.llms.vision_enabled"}}</label>
          <DTooltip
            @icon="circle-question"
            @content={{i18n "discourse_ai.llms.hints.vision_enabled"}}
          />
        </div>
        <div class="control-group ai-llm-editor__enabled-chat-bot">
          <Input @type="checkbox" @checked={{@model.enabled_chat_bot}} />
          <label>{{i18n "discourse_ai.llms.enabled_chat_bot"}}</label>
          <DTooltip
            @icon="circle-question"
            @content={{i18n "discourse_ai.llms.hints.enabled_chat_bot"}}
          />
        </div>

        {{#if @model.user}}
          <div class="control-group">
            <label>{{i18n "discourse_ai.llms.ai_bot_user"}}</label>
            <a
              class="avatar"
              href={{@model.user.path}}
              data-user-card={{@model.user.username}}
            >
              {{Avatar @model.user.avatar_template "small"}}
            </a>
            <LinkTo @route="adminUser" @model={{this.adminUser}}>
              {{@model.user.username}}
            </LinkTo>
          </div>
        {{/if}}

        {{#if this.showQuotas}}
          <div class="control-group">
            <label>{{i18n "discourse_ai.llms.quotas.title"}}</label>
            <AiLlmQuotaEditor
              @model={{@model}}
              @groups={{@groups}}
              @didUpdate={{this.updateQuotaCount}}
            />
          </div>
        {{/if}}

        <div class="control-group ai-llm-editor__action_panel">
          <DButton
            class="ai-llm-editor__test"
            @action={{this.test}}
            @disabled={{this.testRunning}}
            @label="discourse_ai.llms.tests.title"
          />
          {{#if this.showAddQuotaButton}}
            <DButton
              @action={{this.openAddQuotaModal}}
              @label="discourse_ai.llms.quotas.add"
              class="btn"
            />
            {{#if this.modalIsVisible}}
              <AiLlmQuotaModal
                @model={{hash llm=@model}}
                @closeModal={{this.closeAddQuotaModal}}
              />
            {{/if}}
          {{/if}}
          <DButton
            class="btn-primary ai-llm-editor__save"
            @action={{this.save}}
            @disabled={{this.isSaving}}
            @label="discourse_ai.llms.save"
          />
          {{#unless @model.isNew}}
            <DButton
              @action={{this.delete}}
              class="btn-danger ai-llm-editor__delete"
              @label="discourse_ai.llms.delete"
            />
          {{/unless}}
        </div>
      {{/unless}}

      <div class="control-group ai-llm-editor-tests">
        {{#if this.displayTestResult}}
          {{#if this.testRunning}}
            <div class="spinner small"></div>
            {{i18n "discourse_ai.llms.tests.running"}}
          {{else}}
            {{#if this.testResult}}
              <div class="ai-llm-editor-tests__success">
                {{icon "check"}}
                {{i18n "discourse_ai.llms.tests.success"}}
              </div>
            {{else}}
              <div class="ai-llm-editor-tests__failure">
                {{icon "xmark"}}
                {{this.testErrorMessage}}
              </div>
            {{/if}}
          {{/if}}
        {{/if}}
      </div>
    </form>
  </template>
}
