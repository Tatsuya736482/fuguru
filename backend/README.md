# バックエンドセットアップガイド

このガイドでは、Poetry と FastAPI を使用してプロジェクトのバックエンドをセットアップする方法を説明する。

## backend に移動

以下の説明は backend のディレクトリ内にいると前提する

```bash
cd backend
```

## Poetry のインストール

以下の手順に従って Poetry をインストールしてください。
（または[公式サイト](https://python-poetry.org/docs/#installing-with-the-official-installer)を参考）

1. 公式インストーラーを実行します:

   ```bash
   curl -sSL https://install.python-poetry.org | python3 -
   ```

2. Poetry を `PATH` 環境変数に追加する。インストーラーで表示される指示に従い、`poetry` コマンドがターミナルで認識されるように設定してください。
   例は以下。（わからなかったら、ウィンに聞いて）
   `    export PATH="/Users/?????/.local/bin:$PATH"
   `

3. インストールを確認する。

   ```bash
   poetry --version
   ```

   バージョン情報が表示されれば、インストール成功！

## 初期設定

プロジェクトの依存関係をインストールするには、以下のコマンドを実行してください

```bash
poetry install
```

## FastAPI サーバーの起動

1. `src` ディレクトリに移動します:

   ```bash
   cd src
   ```

2. FastAPI 開発サーバーを起動する。

   ```bash
   fastapi dev main.py
   ```

3. 以下見てみて

- http://127.0.0.1:8000
- http://127.0.0.1:8000/docs

## 開発

- 大体、`main.py`を編集する。
- package をインストール場合は

docker tag app gcr.io/fugu-446106/backend

## デプロイ

### 準備

```bash
brew install docker # Dockerをインストール
gcloud auth configure-docker 
chmod +x ./scripts/deploy.sh
```

### スクリプトを実行

```bash
./scripts/deploy.sh
```


## gcloudの認証(tests/test-embed.ipynbのtext_to_vector)
```bash
   gcloud auth application-default set-quota-project fugu-446106
```
(参考: https://cloud.google.com/docs/authentication/adc-troubleshooting/user-creds)

## デットレタートピックの追加
```bash
./scripts/dead_letter_topic.sh  [トリガー名]
```