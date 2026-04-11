import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { next } from "@ember/runloop";
import {
  buildEmojiUrl,
  emojiExists,
  emojiReplacementRegex,
  isCustomEmoji,
} from "pretty-text/emoji";
import { emojiOptions } from "discourse/lib/text";

const MAX_LENGTH = 16;
const MAX_EMOJI = 5;

const UNICODE_EMOJI_REGEX = new RegExp(emojiReplacementRegex, "g");
const EMOJI_SHORTCODE_REGEX = /(^|\W):([^:]+):/;

function getStats(element) {
  let length = 0;
  let emojiCount = 0;

  for (const node of element.childNodes) {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent;
      const unicodeMatches = text.match(UNICODE_EMOJI_REGEX);
      emojiCount += unicodeMatches?.length || 0;
      length += getTextVisibleLength(text);
    } else if (node.nodeName === "IMG" && node.classList.contains("emoji")) {
      length += 1;
      emojiCount += 1;
    }
  }

  return { length, emojiCount };
}

function serialize(element) {
  let result = "";

  for (const node of element.childNodes) {
    if (node.nodeType === Node.TEXT_NODE) {
      result += node.textContent;
    } else if (node.nodeName === "IMG" && node.classList.contains("emoji")) {
      result += node.alt;
    }
  }

  return result;
}

function createEmojiImg(code) {
  const opts = emojiOptions();
  const title = `:${code}:`;
  const src = buildEmojiUrl(code, opts);
  const img = document.createElement("img");
  img.className = isCustomEmoji(code, opts) ? "emoji emoji-custom" : "emoji";
  img.alt = title;
  img.title = title;
  img.src = src;
  return img;
}

function placeCursorAtEnd(element) {
  const range = document.createRange();
  const sel = window.getSelection();
  range.selectNodeContents(element);
  range.collapse(false);
  sel.removeAllRanges();
  sel.addRange(range);
}

function getTextVisibleLength(text) {
  return text.replace(UNICODE_EMOJI_REGEX, "x").length;
}

function getTextOffsetForVisibleOffset(text, visibleOffset) {
  const offset = Math.max(0, visibleOffset ?? 0);
  let actualIndex = 0;
  let visibleIndex = 0;

  for (const match of text.matchAll(UNICODE_EMOJI_REGEX)) {
    const emojiIndex = match.index;
    const plainTextLength = emojiIndex - actualIndex;

    if (offset <= visibleIndex + plainTextLength) {
      return actualIndex + (offset - visibleIndex);
    }

    visibleIndex += plainTextLength;
    if (offset <= visibleIndex + 1) {
      return emojiIndex + match[0].length;
    }

    actualIndex = emojiIndex + match[0].length;
    visibleIndex += 1;
  }

  return Math.min(text.length, actualIndex + (offset - visibleIndex));
}

function getSelectionOffset(container) {
  const selection = window.getSelection();

  if (!selection?.rangeCount) {
    return null;
  }

  const range = selection.getRangeAt(0);
  if (!container.contains(range.startContainer)) {
    return null;
  }

  const preRange = document.createRange();
  preRange.selectNodeContents(container);
  preRange.setEnd(range.startContainer, range.startOffset);
  return serializeRangeContents(preRange);
}

function serializeRangeContents(range) {
  return getStats(range.cloneContents()).length;
}

function setSelectionOffset(container, targetOffset) {
  const selection = window.getSelection();
  const range = document.createRange();
  const offset = Math.max(0, targetOffset ?? 0);
  let traversed = 0;
  const walker = document.createTreeWalker(
    container,
    NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
    {
      acceptNode(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          return NodeFilter.FILTER_ACCEPT;
        }

        if (node.nodeName === "IMG" && node.classList.contains("emoji")) {
          return NodeFilter.FILTER_ACCEPT;
        }

        return NodeFilter.FILTER_SKIP;
      },
    }
  );

  let node;
  while ((node = walker.nextNode())) {
    if (node.nodeType === Node.TEXT_NODE) {
      const textLength = getTextVisibleLength(node.textContent);
      if (offset <= traversed + textLength) {
        range.setStart(
          node,
          getTextOffsetForVisibleOffset(node.textContent, offset - traversed)
        );
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
        return;
      }
      traversed += textLength;
    } else if (node.nodeName === "IMG" && node.classList.contains("emoji")) {
      if (offset <= traversed + 1) {
        if (offset === traversed) {
          range.setStartBefore(node);
        } else {
          range.setStartAfter(node);
        }
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
        return;
      }
      traversed += 1;
    }
  }

  placeCursorAtEnd(container);
}

export default class BoostEditor extends Component {
  @tracked canAddEmoji = true;

  #editor = null;
  #isComposing = false;
  #isApplyingValidation = false;
  #mutationObserver = null;
  #previousHTML = "";
  #previousSelectionOffset = 0;

  willDestroy() {
    super.willDestroy(...arguments);
    this.#mutationObserver?.disconnect();
  }

  @action
  setup(element) {
    this.#editor = element;
    this.#observeEditorMutations();
    this.#previousHTML = element.innerHTML;
    next(() => element.focus());
  }

  @action
  handleInput() {
    if (this.#isComposing) {
      this.#syncEditorState(getStats(this.#editor));
      return;
    }

    this.#enforceFinalizedInput();
  }

  @action
  handleCompositionStart() {
    this.#isComposing = true;
  }

  @action
  handleCompositionEnd() {
    this.#isComposing = false;
    this.#enforceFinalizedInput();
  }

  @action
  handleKeyDown(event) {
    if (this.#isComposing || event.isComposing || event.keyCode === 229) {
      return;
    }

    if (event.key === "Enter") {
      event.preventDefault();
      this.args.onSubmit?.();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.args.onClose?.();
    }
  }

  @action
  handlePaste(event) {
    event.preventDefault();
    const text = event.clipboardData.getData("text/plain");
    document.execCommand("insertText", false, text);
    if (!this.#isComposing) {
      this.#enforceFinalizedInput();
    }
  }

  @action
  insertEmoji(code) {
    const stats = getStats(this.#editor);
    const needsSpace = this.#editor.childNodes.length > 0;
    const extraLength = needsSpace ? 2 : 1;

    if (
      stats.length + extraLength > MAX_LENGTH ||
      stats.emojiCount + 1 > MAX_EMOJI
    ) {
      return;
    }

    if (needsSpace) {
      this.#editor.appendChild(document.createTextNode(" "));
    }

    this.#editor.appendChild(createEmojiImg(code));
    placeCursorAtEnd(this.#editor);
    this.#previousHTML = this.#editor.innerHTML;
    const newStats = getStats(this.#editor);
    this.#previousSelectionOffset = newStats.length;
    this.#syncEditorState(newStats);
  }

  @action
  focus() {
    this.#editor?.focus();
  }

  #updateCanAddEmoji(stats) {
    const spaceNeeded = this.#editor.childNodes.length > 0 ? 2 : 1;
    this.canAddEmoji =
      stats.length + spaceNeeded <= MAX_LENGTH && stats.emojiCount < MAX_EMOJI;
  }

  #enforceFinalizedInput() {
    if (this.#isApplyingValidation || this.#isComposing) {
      return;
    }

    const currentHTML = this.#editor.innerHTML;
    if (currentHTML === this.#previousHTML) {
      return;
    }

    this.#isApplyingValidation = true;
    try {
      const selectionOffset = getSelectionOffset(this.#editor);
      this.#processEmojiShortcodes();

      const stats = getStats(this.#editor);
      if (stats.length > MAX_LENGTH || stats.emojiCount > MAX_EMOJI) {
        this.#editor.innerHTML = this.#previousHTML;
        setSelectionOffset(this.#editor, this.#previousSelectionOffset);
        this.#syncEditorState(getStats(this.#editor));
        return;
      }

      this.#previousHTML = this.#editor.innerHTML;
      this.#previousSelectionOffset = Math.min(
        selectionOffset ?? stats.length,
        stats.length
      );
      this.#syncEditorState(stats);
    } finally {
      this.#isApplyingValidation = false;
    }
  }

  #observeEditorMutations() {
    this.#mutationObserver = new MutationObserver(() => {
      if (this.#isApplyingValidation) {
        return;
      }

      if (this.#isComposing) {
        this.#syncEditorState(getStats(this.#editor));
        return;
      }

      this.#enforceFinalizedInput();
    });

    this.#mutationObserver.observe(this.#editor, {
      childList: true,
      subtree: true,
      characterData: true,
    });
  }

  #syncEditorState(stats) {
    const value = serialize(this.#editor);
    this.#updateCanAddEmoji(stats);
    this.args.onChange?.(value);
  }

  #processEmojiShortcodes() {
    const walker = document.createTreeWalker(
      this.#editor,
      NodeFilter.SHOW_TEXT
    );

    let node;
    while ((node = walker.nextNode())) {
      const match = node.textContent.match(EMOJI_SHORTCODE_REGEX);
      if (match && emojiExists(match[2])) {
        const code = match[2];
        const emojiStart = match.index + match[1].length;
        const emojiEnd = emojiStart + code.length + 2;
        const beforeText = node.textContent.slice(0, emojiStart);
        const afterText = node.textContent.slice(emojiEnd);
        const img = createEmojiImg(code);
        const parent = node.parentNode;

        if (afterText) {
          parent.insertBefore(
            document.createTextNode(afterText),
            node.nextSibling
          );
        }

        parent.insertBefore(img, node.nextSibling);

        if (beforeText) {
          node.textContent = beforeText;
        } else {
          parent.removeChild(node);
        }

        const range = document.createRange();
        const sel = window.getSelection();
        range.setStartAfter(img);
        range.collapse(true);
        sel.removeAllRanges();
        sel.addRange(range);

        break;
      }
    }
  }

  <template>
    {{! template-lint-disable no-invalid-interactive }}
    <div
      class="discourse-boosts__input"
      contenteditable="true"
      data-placeholder={{@placeholder}}
      {{didInsert this.setup}}
      {{on "input" this.handleInput}}
      {{on "compositionstart" this.handleCompositionStart}}
      {{on "compositionend" this.handleCompositionEnd}}
      {{on "keydown" this.handleKeyDown}}
      {{on "paste" this.handlePaste}}
    ></div>
    {{yield
      (hash
        insertEmoji=this.insertEmoji
        focus=this.focus
        canAddEmoji=this.canAddEmoji
      )
    }}
  </template>
}
