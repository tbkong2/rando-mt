// Shared Supabase client for rando-mt (Caption It + anything else that
// needs a real backend). The URL and anon key are meant to ship in client
// code — the anon key only grants what Row Level Security policies allow,
// same pattern as rando's web/config.js.
import 'react-native-url-polyfill/auto';

import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing EXPO_PUBLIC_SUPABASE_URL / EXPO_PUBLIC_SUPABASE_ANON_KEY — check .env'
  );
}

// Web's static pre-render runs in Node, where there is no window and so no
// storage to read a session from. React Native defines window, so phones
// always take the persisted path.
const isServer = typeof window === 'undefined';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    // AsyncStorage persists the session across app restarts; without it
    // every launch would start as a brand-new anonymous session.
    storage: isServer ? undefined : AsyncStorage,
    autoRefreshToken: !isServer,
    persistSession: !isServer,
    detectSessionInUrl: false,
  },
});
