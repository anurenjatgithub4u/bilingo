# Connect OpenAI to BiLingo through Firebase

This sets up the weekly job that creates new questions. Your key stays on Google's servers: it is never in the app, and phones never call OpenAI.

**Project:** `microlearn-e58c9`. Run every command from the `scrollstop` folder.

## 1. Protect your money first

1. In the [OpenAI dashboard](https://platform.openai.com/settings/organization/limits), set a **monthly spending limit**.
2. Create a new API key just for this job. Do not paste it into code, chat or any file.

## 2. Turn on the Blaze plan

Scheduled functions need Firebase's pay-as-you-go plan.

1. [Firebase console](https://console.firebase.google.com/project/microlearn-e58c9/usage/details) → **Modify plan** → **Blaze**.
2. In [Google Cloud Billing → Budgets](https://console.cloud.google.com/billing/budgets), add a small **budget alert**. An alert warns you but does not stop spending.

## 3. Install the Firebase tools and log in

```bash
npm install -g firebase-tools
```

```bash
firebase login
```

## 4. Store the key as a secret

```bash
firebase functions:secrets:set OPENAI_API_KEY
```

It asks for the value, so paste the key there. This is the only place the key goes. It lives in Google Secret Manager, not in Firestore or Remote Config, because phones can read those.

## 5. Publish the database rules

This lets phones read `contentPacks` and stops them writing to it. It replaces the rules currently in your project with `firestore.rules`.

```bash
firebase deploy --only firestore:rules
```

## 6. Deploy the job

```bash
npm --prefix functions install
```

```bash
firebase deploy --only functions
```

If it asks for `OPENAI_MODEL` or `ITEMS_PER_BATCH`, press Enter to accept the defaults, or enter a model your account can use. The defaults are `gpt-4o-mini` and 25 questions per batch.

## 7. Run it once now

The job runs every Monday at 03:00 India time. To run it right away:

1. Open [Cloud Scheduler](https://console.cloud.google.com/cloudscheduler?project=microlearn-e58c9).
2. Find the job with `generateContentPacks` in its name.
3. Choose **Force run**.

## 8. Check the result

```bash
firebase functions:log --only generateContentPacks
```

Look for `Content run finished`, which shows how many questions were published and rejected in each batch. The new packs are in **Firestore → contentPacks**.

Read a sample before you rely on it. Coding answers are proved by running the code, but English and German are only checked for structure, so a wrong meaning or article could get through.

Open the app with internet on. Packs download in the background and show up the next time a feed loads.

## How much it makes

Each run makes 12 batches: 4 subjects × 3 levels × 25 questions, up to 300 questions a week, before rejected ones are removed. To change the amount, redeploy with a different `ITEMS_PER_BATCH`. Maths needs no AI and costs nothing.

## If something goes wrong

| Problem | Likely cause |
|---|---|
| `Batch failed` with `OpenAI 401` | The key is wrong. Repeat step 4, then step 6. |
| `Batch failed` with `OpenAI 429` | No credit or a rate limit on your OpenAI account. |
| `Batch failed` with `OpenAI 404` | The model name isn't available. Set `OPENAI_MODEL` to one your account has. |
| Many `Rejected` lines | Normal in small numbers. If most fail, try a stronger model. |
| Packs exist but don't appear in the app | Step 5 wasn't done, or the phone is offline. |

## If the key ever leaks

Delete it in the OpenAI dashboard, create a new one, then repeat step 4 and step 6.
