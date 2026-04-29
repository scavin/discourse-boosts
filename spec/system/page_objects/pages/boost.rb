# frozen_string_literal: true

module PageObjects
  module Pages
    class Boost < PageObjects::Pages::Base
      def click_post_menu_boost_button(post)
        find("#post_#{post.post_number} .post-action-menu__boost").click
        self
      end

      def fill_in_boost(text)
        editor = find(".discourse-boosts__input-container .discourse-boosts__input")
        editor.send_keys(text)
        self
      end

      def editor_text
        find(".discourse-boosts__input-container .discourse-boosts__input").text
      end

      def has_editor_text?(text)
        has_css?(".discourse-boosts__input-container .discourse-boosts__input", text: text)
      end

      def has_editor?
        has_css?(".discourse-boosts__input-container .discourse-boosts__input")
      end

      def start_boost_composition(text)
        page.execute_script(<<~JS)
          const editor = document.querySelector(".discourse-boosts__input-container .discourse-boosts__input");
          editor.focus();
          editor.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }));
          editor.textContent = #{text.to_json};
          editor.dispatchEvent(new InputEvent("input", {
            bubbles: true,
            data: #{text.to_json},
            inputType: "insertCompositionText",
            isComposing: true
          }));
        JS
        self
      end

      def end_boost_composition
        page.execute_script(<<~JS)
          const editor = document.querySelector(".discourse-boosts__input-container .discourse-boosts__input");
          editor.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true }));
        JS
        self
      end

      def press_boost_key(key, is_composing: false)
        page.execute_script(<<~JS)
          const editor = document.querySelector(".discourse-boosts__input-container .discourse-boosts__input");
          editor.focus();
          const event = new KeyboardEvent("keydown", {
            bubbles: true,
            key: #{key.to_json}
          });

          if (#{is_composing}) {
            Object.defineProperty(event, "isComposing", { configurable: true, get() { return true; } });
            Object.defineProperty(event, "keyCode", { configurable: true, get() { return 229; } });
          }

          editor.dispatchEvent(event);
        JS
        self
      end

      def paste_boost(text)
        page.execute_script(<<~JS)
          const editor = document.querySelector(".discourse-boosts__input-container .discourse-boosts__input");
          editor.focus();
          const dataTransfer = new DataTransfer();
          dataTransfer.setData("text/plain", #{text.to_json});
          editor.dispatchEvent(new ClipboardEvent("paste", {
            bubbles: true,
            clipboardData: dataTransfer
          }));
        JS
        self
      end

      def programmatically_set_boost_html(html, selection_offset: nil)
        page.execute_script(<<~JS)
          const editor = document.querySelector(".discourse-boosts__input-container .discourse-boosts__input");
          editor.innerHTML = #{html.to_json};

          if (#{!selection_offset.nil?}) {
            const targetOffset = #{selection_offset || 0};
            const selection = window.getSelection();
            const range = document.createRange();
            let traversed = 0;

            for (const node of editor.childNodes) {
              if (node.nodeType === Node.TEXT_NODE) {
                const textLength = node.textContent.length;
                if (targetOffset <= traversed + textLength) {
                  range.setStart(node, targetOffset - traversed);
                  range.collapse(true);
                  selection.removeAllRanges();
                  selection.addRange(range);
                  break;
                }
                traversed += textLength;
              } else if (node.nodeName === "IMG" && node.classList.contains("emoji")) {
                if (targetOffset <= traversed + 1) {
                  if (targetOffset === traversed) {
                    range.setStartBefore(node);
                  } else {
                    range.setStartAfter(node);
                  }
                  range.collapse(true);
                  selection.removeAllRanges();
                  selection.addRange(range);
                  break;
                }
                traversed += 1;
              }
            }
          }
        JS
        self
      end

      def programmatically_set_boost_text(text)
        page.execute_script(<<~JS)
          const editor = document.querySelector(".discourse-boosts__input-container .discourse-boosts__input");
          editor.textContent = #{text.to_json};
        JS
        self
      end

      def editor_selection_offset
        page.evaluate_script(<<~JS)
          (() => {
            const editor = document.querySelector(".discourse-boosts__input-container .discourse-boosts__input");
            const selection = window.getSelection();

            if (!selection || selection.rangeCount === 0) {
              return null;
            }

            const range = selection.getRangeAt(0);
            if (!editor.contains(range.startContainer)) {
              return null;
            }

            const preRange = document.createRange();
            preRange.selectNodeContents(editor);
            preRange.setEnd(range.startContainer, range.startOffset);

            const wrapper = document.createElement("div");
            wrapper.appendChild(preRange.cloneContents());

            let offset = 0;
            for (const node of wrapper.childNodes) {
              if (node.nodeType === Node.TEXT_NODE) {
                offset += node.textContent.length;
              } else if (node.nodeName === "IMG" && node.classList.contains("emoji")) {
                offset += 1;
              }
            }

            return offset;
          })()
        JS
      end

      def has_editor_selection_offset?(offset)
        page.document.synchronize do
          raise Capybara::ExpectationNotMet unless editor_selection_offset == offset
        end

        true
      rescue Capybara::ExpectationNotMet
        false
      end

      def submit_boost
        find(".discourse-boosts__submit").click
        self
      end

      def has_boost?(post, cooked_content = nil)
        selector = "#post_#{post.post_number} .discourse-boosts .discourse-boosts__cooked"
        if cooked_content
          has_css?("#{selector} img.emoji[alt='#{cooked_content}']")
        else
          has_css?(selector)
        end
      end

      def click_boost_cooked(post)
        find("#post_#{post.post_number} .discourse-boosts button.discourse-boosts__cooked").click
        self
      end

      def click_flag_boost(post)
        find("#post_#{post.post_number} .discourse-boosts__flag").click
        self
      end

      def click_delete_boost(post)
        find("#post_#{post.post_number} .discourse-boosts__delete").click
        self
      end

      def has_no_boosts?(post)
        has_no_css?("#post_#{post.post_number} .discourse-boosts")
      end

      def has_no_boost?(post)
        has_no_boosts?(post)
      end

      def has_post_menu_boost_button?(post)
        has_css?("#post_#{post.post_number} .post-action-menu__boost")
      end

      def has_no_post_menu_boost_button?(post)
        has_no_css?("#post_#{post.post_number} .post-action-menu__boost")
      end

      def has_boosts_list_boost_button?(post)
        has_css?("#post_#{post.post_number} .discourse-boosts__add-btn")
      end

      def has_no_boosts_list_boost_button?(post)
        has_no_css?("#post_#{post.post_number} .discourse-boosts__add-btn")
      end
    end
  end
end
