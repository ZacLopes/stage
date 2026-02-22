# 🛡️ Security Enhancements - Deployment Guide

## Overview
This guide walks you through deploying the security enhancements for the Career Gamification app. These changes protect your OpenAI API key, implement rate limiting, and restrict database access.

---

## 📋 Prerequisites

1. **Supabase CLI installed**:
   ```bash
   brew install supabase/tap/supabase
   ```

2. **Supabase project linked**:
   ```bash
   supabase link --project-ref your-project-ref
   ```

3. **OpenAI API Key** ready

---

## 🚀 Deployment Steps

### Step 1: Apply Database Security Enhancements

Run the security SQL script in your Supabase SQL Editor:

1. Go to your Supabase Dashboard → SQL Editor
2. Create a new query
3. Copy and paste the contents of `supabase/security_enhancements.sql`
4. Click "Run"

This will:
- ✅ Create `ai_generation_logs` table for rate limiting
- ✅ Restrict RLS policies on content tables (tracks, phases, questions)
- ✅ Create security audit log table
- ✅ Add helper functions for rate limiting

---

### Step 2: Deploy Edge Functions

Deploy all three Edge Functions to Supabase:

```bash
# Deploy generate-profile function
supabase functions deploy generate-profile

# Deploy generate-resume function
supabase functions deploy generate-resume

# Deploy generate-interview-report function
supabase functions deploy generate-interview-report
```

---

### Step 3: Set OpenAI API Key Secret

Set your OpenAI API key as a Supabase secret (it will be accessible only to Edge Functions):

```bash
supabase secrets set OPENAI_API_KEY=your_actual_openai_api_key_here
```

**Verify the secret was set:**
```bash
supabase secrets list
```

You should see `OPENAI_API_KEY` in the list.

---

### Step 4: Update Flutter Dependencies

Remove the `dart_openai` dependency since we no longer call OpenAI directly from the client:

```bash
flutter pub remove dart_openai
flutter pub get
```

---

### Step 5: Update Your Local .env File

Remove the `OPENAI_API_KEY` line from your `.env` file (keep only Supabase credentials):

```env
# Supabase Configuration
SUPABASE_URL=your_supabase_url_here
SUPABASE_ANON_KEY=your_supabase_anon_key_here
```

---

### Step 6: Test the Edge Functions

Test each Edge Function to ensure they're working:

#### Test generate-profile:
```bash
supabase functions serve generate-profile
```

Then in another terminal:
```bash
curl -i --location --request POST 'http://localhost:54321/functions/v1/generate-profile' \
  --header 'Authorization: Bearer YOUR_SUPABASE_ANON_KEY' \
  --header 'Content-Type: application/json' \
  --data '{"answersWithQuestions":{"test":"test"}}'
```

#### Test generate-resume:
```bash
supabase functions serve generate-resume
```

#### Test generate-interview-report:
```bash
supabase functions serve generate-interview-report
```

---

### Step 7: Build and Test the Flutter App

```bash
# Clean build
flutter clean
flutter pub get

# Run the app
flutter run
```

**Test the following features:**
1. ✅ Profile generation (should call Edge Function)
2. ✅ Resume generation (should call Edge Function)
3. ✅ Interview report generation (should call Edge Function)
4. ✅ Rate limiting (try generating more than the daily limit)

---

## 🔒 Security Improvements Summary

| Feature | Before | After |
|---------|--------|-------|
| **OpenAI API Key** | 🔴 Exposed in client app | ✅ Secure in Edge Functions only |
| **Rate Limiting** | 🔴 None | ✅ 20 profiles, 10 resumes, 5 interviews per day |
| **Content RLS** | 🟡 Anyone can insert/update | ✅ Read-only for users |
| **API Cost Control** | 🔴 Unlimited usage | ✅ Tracked and limited per user |
| **Audit Logging** | 🔴 None | ✅ All AI generations logged |

---

## 📊 Rate Limits

| Generation Type | Daily Limit | Edge Function |
|----------------|-------------|---------------|
| Profile | 20 | `generate-profile` |
| Resume | 10 | `generate-resume` |
| Interview Report | 5 | `generate-interview-report` |

Users will receive a `429 Rate Limit Exceeded` error if they exceed these limits.

---

## 🔍 Monitoring

### View AI Generation Logs

```sql
SELECT 
  user_id,
  generation_type,
  tokens_used,
  created_at
FROM ai_generation_logs
ORDER BY created_at DESC
LIMIT 100;
```

### Check Rate Limit for a User

```sql
SELECT 
  generation_type,
  COUNT(*) as count,
  SUM(tokens_used) as total_tokens
FROM ai_generation_logs
WHERE user_id = 'user-uuid-here'
  AND created_at >= CURRENT_DATE
GROUP BY generation_type;
```

---

## 🐛 Troubleshooting

### Edge Function returns 401 Unauthorized
- **Cause**: User not authenticated
- **Fix**: Ensure the Flutter app is sending the Authorization header with a valid JWT token

### Edge Function returns 500 Internal Server Error
- **Cause**: OpenAI API key not set or invalid
- **Fix**: Run `supabase secrets set OPENAI_API_KEY=your_key`

### Edge Function returns 429 Rate Limit Exceeded
- **Cause**: User exceeded daily limit
- **Fix**: This is expected behavior. Wait until the next day or increase limits in the Edge Function code

### "Cannot find module" errors in TypeScript files
- **Cause**: These are expected lint errors for Deno modules
- **Fix**: These errors are harmless and won't affect deployment. Deno runtime will resolve them correctly.

---

## 🎯 Next Steps (Optional Enhancements)

1. **Enable Code Obfuscation** (for production builds):
   ```bash
   flutter build apk --obfuscate --split-debug-info=build/debug-info
   ```

2. **Set up pg_cron** for automatic log cleanup:
   - Enable pg_cron extension in Supabase Dashboard
   - Schedule the cleanup function to run daily

3. **Implement App Check** (Firebase/Supabase):
   - Prevents API calls from unauthorized sources
   - Ensures requests come from your legitimate app

4. **Monitor OpenAI Costs**:
   - Set up billing alerts in OpenAI Dashboard
   - Review `tokens_used` in `ai_generation_logs` regularly

---

## ✅ Deployment Checklist

- [ ] Applied `security_enhancements.sql` in Supabase SQL Editor
- [ ] Deployed all 3 Edge Functions
- [ ] Set `OPENAI_API_KEY` secret in Supabase
- [ ] Removed `dart_openai` from `pubspec.yaml`
- [ ] Updated `.env` file (removed OPENAI_API_KEY)
- [ ] Tested all AI generation features
- [ ] Verified rate limiting works
- [ ] Checked logs in `ai_generation_logs` table

---

## 📞 Support

If you encounter any issues during deployment, check:
1. Supabase Dashboard → Edge Functions → Logs
2. Supabase Dashboard → Database → Logs
3. Flutter app console output

---

**🎉 Congratulations!** Your app is now significantly more secure. The OpenAI API key is protected, rate limiting is in place, and you have full audit trails of all AI generations.
