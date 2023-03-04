AskGPT.vim
==========

VimにChatGPTを組み込んで、あなたのコードについて質問できるようにするプラグイン。

__注意__: 実験的なプラグインです。あまりテストされていませんので、十分注意して使用してください。

English version of readme (that was translated via this plugin!), follows Japanese version.

![Screenshot of this plugin. There are two windows, left is Japanese version of this readme, and right is a chat window that AskGPT is translating it to English.](./screenshot.jpg)


## 必要なもの

- `+job`と`+channel`が有効になっているVim。
- `curl`コマンド。
- OpenAIのAPIキー。


## 使い方

1. vimrcでAPIキーを設定する。

```vim
let g:askgpt_api_key = 'xxxxxxxxxxxxxxxxxxxx'
```

2. Vimを起動して、`:AskGPT`でチャットウィンドウを開く。

3. 聞きたいことを入力してエンターを押す。


## ヒントと注意事項

- `:[range]AskGPT`として範囲付きでコマンドを実行すると、その範囲をChatGPTにシェアすることができます。

  * コードについて質問したいときは、ビジュアルモードで選択してから`:'<,'>AskGPT`のように起動すると便利です。

  * `:%AskGPT`のようにすれば、コード全体について質問できます。

- `:AskGPT [聞きたいこと]`のように実行すると、コマンドから直接質問を入力できます。

- デフォルトでは過去10件のメッセージと共有したコードがChatGPT APIに送信されます。文字数等での上限は設けていませんので、APIの使用状況に注意しながら利用してください。

  * APIに送信するメッセージの件数は`g:askgpt_history_size`で変更できます。

  * メッセージ履歴は`:AskGPT!`で削除できます。

---

A plugin that integrates ChatGPT into Vim to let you ask questions about your code.

__Note__: This is an experimental plugin and has not been thoroughly tested, so please use it with caution.


## Requirements

- Vim with `+job` and `+channel` enabled.
- `curl` command.
- OpenAI API key.


## How to use

1. Set your OpenAI API key in your vimrc.

```vim
let g:askgpt_api_key = 'xxxxxxxxxxxxxxxxxxxx'
```

2. Open Vim and use the `:AskGPT` command to open the chat window.

3. Enter your question and press Enter.


## Hints and Cautions

- You can share a range with ChatGPT by executing the `:[range]AskGPT` command.

  * When you want to ask about a piece of code, it's convenient to select it in Visual mode and execute the `:'<,'>AskGPT` command.

  * You can ask a question about the whole file by executing the `:%AskGPT` command.

- You can enter your question directly from the command line by executing the `:AskGPT [your question]` command.

- By default, the last 10 messages and shared code will be sent to the ChatGPT API. There is no limit on the number of characters, so use it carefully.

  * You can change the number of messages to send through `g:askgpt_history_size`.

  * The message history can be deleted with `:AskGPT!`.
