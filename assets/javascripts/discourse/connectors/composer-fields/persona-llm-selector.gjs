import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { next } from "@ember/runloop";
import { inject as service } from "@ember/service";
import KeyValueStore from "discourse/lib/key-value-store";
import DropdownSelectBox from "select-kit/components/dropdown-select-box";

function isBotMessage(composer, currentUser) {
  if (
    composer &&
    composer.targetRecipients &&
    currentUser.ai_enabled_chat_bots
  ) {
    const reciepients = composer.targetRecipients.split(",");

    return currentUser.ai_enabled_chat_bots
      .filter((bot) => !bot.is_persona)
      .any((bot) => reciepients.any((username) => username === bot.username));
  }
  return false;
}

export default class BotSelector extends Component {
  static shouldRender(args, container) {
    return (
      container?.currentUser?.ai_enabled_personas &&
      isBotMessage(args.model, container.currentUser)
    );
  }

  @service currentUser;
  @service siteSettings;
  @tracked llm;
  @tracked allowLLMSelector = true;

  STORE_NAMESPACE = "discourse_ai_persona_selector_";
  LLM_STORE_NAMESPACE = "discourse_ai_llm_selector_";

  preferredPersonaStore = new KeyValueStore(this.STORE_NAMESPACE);
  preferredLlmStore = new KeyValueStore(this.LLM_STORE_NAMESPACE);

  constructor() {
    super(...arguments);

    if (this.botOptions && this.composer) {
      let personaId = this.preferredPersonaStore.getObject("id");

      this._value = this.botOptions[0].id;
      if (personaId) {
        personaId = parseInt(personaId, 10);
        if (this.botOptions.any((bot) => bot.id === personaId)) {
          this._value = personaId;
        }
      }

      this.composer.metaData = { ai_persona_id: this._value };
      this.setAllowLLMSelector();

      let llm = this.preferredLlmStore.getObject("id");
      llm = llm || this.llmOptions[0].id;
      if (llm) {
        next(() => {
          this.currentLlm = llm;
        });
      }
    }
  }

  get composer() {
    return this.args?.outletArgs?.model;
  }

  get botOptions() {
    if (this.currentUser.ai_enabled_personas) {
      return this.currentUser.ai_enabled_personas.map((persona) => {
        return {
          id: persona.id,
          name: persona.name,
          description: persona.description,
        };
      });
    }
  }

  get filterable() {
    return this.botOptions.length > 4;
  }

  get value() {
    return this._value;
  }

  set value(newValue) {
    this._value = newValue;
    this.preferredPersonaStore.setObject({ key: "id", value: newValue });
    this.composer.metaData = { ai_persona_id: newValue };
    this.setAllowLLMSelector();
  }

  setAllowLLMSelector() {
    const persona = this.currentUser.ai_enabled_personas.find(
      (innerPersona) => innerPersona.id === this._value
    );

    this.allowLLMSelector = !persona?.force_default_llm;
  }

  get currentLlm() {
    return this.llm;
  }

  set currentLlm(newValue) {
    this.llm = newValue;
    const botUsername = this.currentUser.ai_enabled_chat_bots.find(
      (bot) => bot.model_name === this.llm
    ).username;
    this.preferredLlmStore.setObject({ key: "id", value: newValue });
    if (this.allowLLMSelector) {
      this.composer.set("targetRecipients", botUsername);
    } else {
      const persona = this.currentUser.ai_enabled_personas.find(
        (innerPersona) => innerPersona.id === this._value
      );
      this.composer.set("targetRecipients", persona.username || "");
    }
  }

  get llmOptions() {
    const availableBots = this.currentUser.ai_enabled_chat_bots
      .filter((bot) => !bot.is_persona)
      .filter(Boolean);

    return availableBots.map((bot) => {
      return {
        id: bot.model_name,
        name: bot.display_name,
      };
    });
  }

  <template>
    <div class="persona-llm-selector">
      <div class="gpt-persona">
        <DropdownSelectBox
          class="persona-llm-selector__persona-dropdown"
          @value={{this.value}}
          @content={{this.botOptions}}
          @options={{hash icon="robot" filterable=this.filterable}}
        />
      </div>
      {{#if this.allowLLMSelector}}
        <div class="llm-selector">
          <DropdownSelectBox
            class="persona-llm-selector__llm-dropdown"
            @value={{this.currentLlm}}
            @content={{this.llmOptions}}
            @options={{hash icon="globe"}}
          />
        </div>
      {{/if}}
    </div>
  </template>
}
