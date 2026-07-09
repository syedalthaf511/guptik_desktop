import 'package:postgres/postgres.dart';
import 'dart:math';
import 'dart:convert'; // 🚀 CRITICAL: Required for JSON encoding the Trust Me encryption keys!

/// PostgresService — The Master Database Architect
/// This service connects to the local Docker PostgreSQL container.
/// It is responsible for creating the databases for Vault, Ollama,
/// and the highly secure Trust Me P2P encrypted messaging system.
class PostgresService {
  // Singleton Pattern
  static final PostgresService _instance = PostgresService._internal();
  factory PostgresService() => _instance;
  PostgresService._internal();

  String _generateSecureToken() {
    const chars =
        'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final rnd = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(32, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  // The active connection
  Connection? _connection;
  bool _isConnected = false;

  // Master System Password (Must match your docker-compose.yml)
  static const String dockerMasterPassword = "GuptikSystemPassword2026";

  // ==============================================================================
  // SECTION 1: CONNECTION MANAGEMENT
  // ==============================================================================
  // These methods handle the raw TCP connections between the Flutter Desktop App
  // and the local Docker PostgreSQL container running on port 55432.

  Future<void> connect() async {
    if (_connection != null && _connection!.isOpen) return;

    print("🔌 Connecting to Database...");
    try {
      _connection = await Connection.open(
        Endpoint(
          host: 'localhost',
          port: 55432,
          database: 'postgres',
          username: 'postgres',
          password: dockerMasterPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      _isConnected = true;
      print("✅ Database Connected!");
      // 🚀 THE MIGRATION FIX: Check and add the column every time we connect!
      try {
        await _connection!.execute('ALTER TABLE tm_contacts ADD COLUMN IF NOT EXISTS custom_username TEXT;');
        print("✅ DB Check: custom_username column is ready.");
      } catch (_) {}

    } catch (e) {
      print("❌ Database Connection Failed: $e");
    }
  }

  Future<void> close() async {
    await _connection?.close();
    _isConnected = false;
    print("🔌 Database Disconnected");
  }
  Future<void> connectExistingUser({
    required String email,
    required String userPassword,
  }) async {
    try {
      final safeUser = email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      _connection = await Connection.open(
        Endpoint(
          host: '127.0.0.1',
          port: 55432,
          database: 'postgres',
          username: safeUser,
          password: userPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      _isConnected = true;
      print("DB: Re-connected successfully as $safeUser");
// 🚀 THE MIGRATION FIX: Check and add the column every time we connect!
      try {
        await _connection!.execute('ALTER TABLE tm_contacts ADD COLUMN IF NOT EXISTS custom_username TEXT;');
      } catch (_) {}

    } catch (e) {
      print("DB Re-connect Error: $e");
      rethrow;
    }
  }
  // ==============================================================================
  // SECTION 2: INITIALIZATION & TABLE SETUP
  // ==============================================================================
  // When the user first registers, this boots up the database, creates their
  // secure Postgres User Role, and runs the massive schema generation below.

  Future<void> initializeUserDatabase({
    required String email,
    required String userPassword,
  }) async {
    Connection? rootConn;
    int retries = 0;
    const int maxRetries = 100;

    // Retry Loop: Docker containers take a few seconds to boot up
    while (retries < maxRetries) {
      try {
        rootConn = await Connection.open(
          Endpoint(
            host: 'localhost',
            port: 55432,
            database: 'postgres',
            username: 'postgres',
            password: dockerMasterPassword,
          ),
          settings: const ConnectionSettings(
            sslMode: SslMode.disable,
            connectTimeout: Duration(seconds: 3),
            queryTimeout: Duration(seconds: 5),
          ),
        );
        await rootConn.execute("SELECT 1");
        break;
      } catch (e) {
        retries++;
        try {
          await rootConn?.close();
        } catch (_) {}
        print("Waiting for DB... ($retries/$maxRetries)");
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (rootConn == null) throw Exception("Database failed to start in time.");

    try {
      final safeUser = email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      // 1. Run the massive schema setup as SUPERUSER
      await setupDefaultDatabase(rootConn);

      // 2. Create the specific User Role for security
      final checkRole = await rootConn.execute(
        "SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = '$safeUser'",
      );
      if (checkRole.isEmpty) {
        final safePass = userPassword.replaceAll("'", "''");
        await rootConn.execute(
          "CREATE ROLE $safeUser LOGIN PASSWORD '$safePass'",
        );
      }

      // 3. Grant privileges to the new user
      await rootConn.execute(
        "GRANT ALL PRIVILEGES ON DATABASE postgres TO $safeUser",
      );
      await rootConn.execute(
        'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $safeUser;',
      );
      await rootConn.execute(
        'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $safeUser;',
      );

      await rootConn.close();

      // 4. Re-connect as the newly created normal user
      _connection = await Connection.open(
        Endpoint(
          host: '127.0.0.1',
          port: 55432,
          database: 'postgres',
          username: safeUser,
          password: userPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      _isConnected = true;
      print("DB: Connected as $safeUser");
    } catch (e) {
      print("DB Init Error: $e");
      rethrow;
    }
  }

  /// THE MASTER ARCHITECT: Creates all necessary tables for the entire system
  Future<void> setupDefaultDatabase(Connection conn) async {
    try {
      await conn.execute('GRANT ALL ON SCHEMA public TO public');
    } catch (_) {}

    // -------------------------------------------------------------------------
    // PART A: VAULT SYSTEM SCHEMA
    // -------------------------------------------------------------------------
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS vault_files (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_size BIGINT,
        mime_type TEXT,
        is_favorite BOOLEAN DEFAULT FALSE,
        added_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS vault_share_file (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        file_name TEXT NOT NULL,
        emails_access_to TEXT[], 
        access_token TEXT,
        is_public BOOLEAN DEFAULT FALSE,
        expires_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    // -------------------------------------------------------------------------
    // PART B: OLLAMA AI 
    // -------------------------------------------------------------------------
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS ollama_models (
        model_tag TEXT PRIMARY KEY,
        system_prompt TEXT,
        size_bytes BIGINT,
        description TEXT,
        parameter_size TEXT,
        is_active BOOLEAN DEFAULT TRUE,
        pulled_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS ollama_chat_memory (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        session_id TEXT NOT NULL,
        model_used TEXT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');



    // -------------------------------------------------------------------------
    // PART C: TRUST ME (V1 ENTERPRISE SCHEMA) 🚀
    // -------------------------------------------------------------------------

    // Enable cryptographic extensions
    await conn.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"');
    await conn.execute('CREATE EXTENSION IF NOT EXISTS "pgcrypto"');

    // 1. IDENTITY
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_identity (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        guptik_user_id TEXT NOT NULL,
        username TEXT NOT NULL,
        identity_public_key TEXT NOT NULL,
        identity_private_key_enc TEXT NOT NULL,
        signed_prekey_public TEXT NOT NULL,
        signed_prekey_private_enc TEXT NOT NULL,
        signed_prekey_id INTEGER NOT NULL DEFAULT 1,
        signed_prekey_signature TEXT NOT NULL,
        signed_prekey_created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        one_time_prekeys JSONB NOT NULL DEFAULT '[]'::jsonb,
        one_time_prekeys_count INTEGER NOT NULL DEFAULT 0,
        device_fingerprint TEXT NOT NULL,
        device_type TEXT NOT NULL DEFAULT 'desktop',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    // 2. CONTACTS & INDICES
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_contacts (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        contact_guptik_id TEXT NOT NULL UNIQUE,
        contact_username TEXT NOT NULL,
        custom_username TEXT,
        contact_cloudflare_url TEXT NOT NULL,
        contact_identity_pubkey TEXT NOT NULL,
        contact_signed_prekey TEXT NOT NULL,
        contact_signed_prekey_id INTEGER NOT NULL,
        ratchet_state_enc TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        conversation_id UUID UNIQUE,
        handshake_id UUID,
        established_at TIMESTAMPTZ,
        last_message_at TIMESTAMPTZ,
        last_seen_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    
    // SAFEGUARD
    try {
      await conn.execute('ALTER TABLE tm_contacts ADD COLUMN IF NOT EXISTS custom_username TEXT;');
    } catch (_) {}

    await conn.execute('CREATE INDEX IF NOT EXISTS idx_tm_contacts_username ON tm_contacts(contact_username)');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_tm_contacts_status ON tm_contacts(status)');

    // 3. HANDSHAKE SESSIONS
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_handshake_sessions (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        initiated_by TEXT NOT NULL,
        counterpart_username TEXT,
        counterpart_guptik_id TEXT,
        counterpart_cloudflare_url TEXT,
        code_6digit TEXT NOT NULL,
        code_hash TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        live_window_start TIMESTAMPTZ,
        live_window_expires_at TIMESTAMPTZ,
        status TEXT NOT NULL DEFAULT 'code_generated',
        my_ephemeral_pubkey TEXT,
        their_key_bundle_snapshot JSONB,
        resulting_contact_id UUID,
        notes TEXT,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    await conn.execute(
      'CREATE INDEX IF NOT EXISTS idx_tm_handshake_status ON tm_handshake_sessions(status)',
    );

    // 4. PENDING REQUESTS
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_pending_requests (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        handshake_session_id UUID,
        direction TEXT NOT NULL,
        counterpart_username TEXT NOT NULL,
        counterpart_guptik_id TEXT,
        counterpart_cloudflare_url TEXT,
        counterpart_public_key TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        resolved_at TIMESTAMPTZ,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_tm_pending_direction ON tm_pending_requests(direction, status)');

    // 5. CONVERSATIONS
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_conversations (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        type TEXT NOT NULL,
        contact_id UUID,
        group_id UUID,
        unknown_sender_id TEXT,
        last_message_preview TEXT,
        last_message_at TIMESTAMPTZ,
        last_message_type TEXT,
        unread_count INTEGER NOT NULL DEFAULT 0,
        is_muted BOOLEAN NOT NULL DEFAULT FALSE,
        is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
        is_archived BOOLEAN NOT NULL DEFAULT FALSE,
        source_type TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_tm_conversations_type ON tm_conversations(type)');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_tm_conversations_last_msg ON tm_conversations(last_message_at DESC)');

    // 6. MESSAGES
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_messages (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        conversation_id UUID NOT NULL,
        sender_guptik_id TEXT NOT NULL,
        sender_username TEXT NOT NULL,
        content_encrypted TEXT,
        content_type TEXT NOT NULL DEFAULT 'text',
        message_nonce TEXT NOT NULL,
        reply_to_message_id UUID,
        reaction_to_message_id UUID,
        reaction_emoji TEXT,
        media_vault_url_enc TEXT,
        media_vault_key_enc TEXT,
        media_thumbnail_enc TEXT,
        media_file_size BIGINT,
        media_duration_secs INTEGER,
        media_mime_type TEXT,
        media_downloaded BOOLEAN DEFAULT FALSE,
        media_local_vault_path TEXT,
        is_read BOOLEAN NOT NULL DEFAULT FALSE,
        is_delivered BOOLEAN NOT NULL DEFAULT FALSE,
        is_deleted_for_everyone BOOLEAN NOT NULL DEFAULT FALSE,
        deleted_at TIMESTAMPTZ,
        sent_at TIMESTAMPTZ,
        delivered_at TIMESTAMPTZ,
        read_at TIMESTAMPTZ,
        received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        ratchet_message_number INTEGER,
        ratchet_chain_id TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_tm_messages_conversation ON tm_messages(conversation_id, received_at DESC)');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_tm_messages_unread ON tm_messages(conversation_id, is_read) WHERE is_read = FALSE');

    // 7. OUTGOING QUEUE
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_outgoing_queue (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        recipient_guptik_id TEXT NOT NULL,
        recipient_cloudflare_url TEXT NOT NULL,
        recipient_username TEXT NOT NULL,
        message_payload_enc TEXT NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'direct',
        group_id UUID,
        status TEXT NOT NULL DEFAULT 'queued',
        retry_count INTEGER NOT NULL DEFAULT 0,
        max_retries INTEGER NOT NULL DEFAULT 50,
        last_attempt_at TIMESTAMPTZ,
        next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deliver_by TIMESTAMPTZ,
        priority INTEGER NOT NULL DEFAULT 5,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_tm_queue_status ON tm_outgoing_queue(status, next_attempt_at)');

    // 8. GROUPS
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_groups (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        group_name TEXT NOT NULL,
        group_description TEXT,
        group_avatar_vault_url TEXT,
        host_mode TEXT NOT NULL DEFAULT 'specific_hosts',
        admin_guptik_id TEXT NOT NULL,
        admin_username TEXT NOT NULL,
        invite_code TEXT UNIQUE,
        invite_expiry TIMESTAMPTZ,
        group_key_version INTEGER NOT NULL DEFAULT 1,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_group_members (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        group_id UUID NOT NULL,
        member_guptik_id TEXT NOT NULL,
        member_username TEXT NOT NULL,
        member_cloudflare_url TEXT NOT NULL,
        member_identity_pubkey TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'member',
        is_online BOOLEAN NOT NULL DEFAULT FALSE,
        last_seen_in_group TIMESTAMPTZ,
        joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        invited_by_guptik_id TEXT,
        group_key_enc TEXT NOT NULL,
        group_key_version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(group_id, member_guptik_id)
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_group_sync_log (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        group_id UUID NOT NULL,
        event_type TEXT NOT NULL,
        event_data_enc TEXT NOT NULL,
        event_sequence BIGINT NOT NULL,
        synced_by_host_id TEXT NOT NULL,
        synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        is_distributed BOOLEAN NOT NULL DEFAULT FALSE
      )
    ''');

    // 9. PRESENCE
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_presence (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        guptik_id TEXT NOT NULL UNIQUE,
        username TEXT NOT NULL,
        is_online BOOLEAN NOT NULL DEFAULT FALSE,
        active_conversation_id UUID,
        active_conversation_partner TEXT,
        device_type TEXT DEFAULT 'desktop',
        last_heartbeat TIMESTAMPTZ,
        last_seen TIMESTAMPTZ,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    // 10. UNKNOWN INBOX
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_unknown_inbox (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        source_type TEXT NOT NULL,
        sender_identifier TEXT NOT NULL,
        sender_username TEXT,
        sender_cloudflare_url TEXT,
        sender_public_key TEXT,
        content_encrypted TEXT,
        content_type TEXT NOT NULL DEFAULT 'text',
        media_vault_url_enc TEXT,
        is_read BOOLEAN NOT NULL DEFAULT FALSE,
        action_taken TEXT,
        action_at TIMESTAMPTZ,
        security_scan_result TEXT,
        security_scan_at TIMESTAMPTZ,
        received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    // 11. MESSAGE REACTIONS
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_message_reactions (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        message_id UUID NOT NULL,
        reactor_guptik_id TEXT NOT NULL,
        reactor_username TEXT NOT NULL,
        emoji TEXT NOT NULL,
        reacted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(message_id, reactor_guptik_id)
      )
    ''');

    // 12. SECURITY LOGS & BLOCKED USERS
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_blocked_users (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        blocked_guptik_id TEXT NOT NULL UNIQUE,
        blocked_username TEXT,
        blocked_cloudflare_url TEXT,
        reason TEXT,
        blocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_security_log (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        event_type TEXT NOT NULL,
        source_ip TEXT,
        source_guptik_id TEXT,
        details JSONB,
        severity TEXT NOT NULL DEFAULT 'info',
        occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    // 13. PL/PGSQL TRIGGER (Presence Notify)
    await conn.execute('''
      CREATE OR REPLACE FUNCTION notify_presence_change()
      RETURNS TRIGGER AS \$\$
      BEGIN
        PERFORM pg_notify(
          'presence_changed',
          json_build_object(
            'guptik_id', NEW.guptik_id,
            'username', NEW.username,
            'is_online', NEW.is_online,
            'active_conversation_partner', NEW.active_conversation_partner,
            'updated_at', NEW.updated_at
          )::text
        );
        RETURN NEW;
      END;
      \$\$ LANGUAGE plpgsql
    ''');

    await conn.execute('DROP TRIGGER IF EXISTS tm_presence_notify ON tm_presence');
    await conn.execute('''
      CREATE TRIGGER tm_presence_notify
        AFTER INSERT OR UPDATE ON tm_presence
        FOR EACH ROW EXECUTE FUNCTION notify_presence_change()
    ''');

    // -------------------------------------------------------------------------
    // 🚀 PART D: GUPTIK PLAYER (MEDIA ECOSYSTEM)
    // -------------------------------------------------------------------------
    
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_channels (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        channel_id TEXT NOT NULL UNIQUE,
        user_id UUID NOT NULL,
        channel_name TEXT NOT NULL,
        bio TEXT DEFAULT '',
        avatar_path TEXT,
        banner_path TEXT,
        subscriber_count INTEGER DEFAULT 0,
        total_views INTEGER DEFAULT 0,
        verified BOOLEAN DEFAULT FALSE,
        location TEXT DEFAULT '',
        language TEXT DEFAULT 'en',
        category_tags TEXT[] DEFAULT '{}',
        monetization_enabled BOOLEAN DEFAULT FALSE,
        stripe_connected BOOLEAN DEFAULT FALSE,
        payout_email TEXT,
        total_earnings_local DECIMAL DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_videos (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        channel_id TEXT NOT NULL REFERENCES mp_channels(channel_id),
        title TEXT NOT NULL,
        description TEXT DEFAULT '',
        tags TEXT[] DEFAULT '{}',
        creator_tags TEXT[] DEFAULT '{}',
        community_tags TEXT[] DEFAULT '{}',
        file_path TEXT NOT NULL,
        thumbnail_path TEXT,
        preview_gif_path TEXT,
        upload_timestamp TIMESTAMPTZ DEFAULT NOW(),
        duration_seconds INTEGER,
        qualities JSONB DEFAULT '{}',
        language TEXT DEFAULT 'en',
        location TEXT,
        visibility TEXT DEFAULT 'public',
        is_reel BOOLEAN DEFAULT FALSE,
        is_live BOOLEAN DEFAULT FALSE,
        live_start_timestamp TIMESTAMPTZ,
        live_ended_timestamp TIMESTAMPTZ,
        category TEXT,
        age_rating TEXT DEFAULT 'all',
        copyright_info TEXT,
        monetization_enabled BOOLEAN DEFAULT FALSE,
        sticker_products JSONB DEFAULT '[]',
        sticker_services JSONB DEFAULT '[]',
        view_count_local INTEGER DEFAULT 0,
        like_count_local INTEGER DEFAULT 0,
        repost_count_local INTEGER DEFAULT 0,
        save_count_local INTEGER DEFAULT 0,
        comment_count_local INTEGER DEFAULT 0,
        share_count_local INTEGER DEFAULT 0,
        playlist_count_local INTEGER DEFAULT 0,
        reaction_heart_count INTEGER DEFAULT 0,
        reaction_fire_count INTEGER DEFAULT 0,
        reaction_thumbs_up_count INTEGER DEFAULT 0,
        reaction_clap_count INTEGER DEFAULT 0,
        reaction_laugh_count INTEGER DEFAULT 0,
        reaction_surprised_count INTEGER DEFAULT 0,
        reaction_sad_count INTEGER DEFAULT 0,
        average_watch_percentage DECIMAL DEFAULT 0,
        unique_viewers_local INTEGER DEFAULT 0,
        is_deleted BOOLEAN DEFAULT FALSE,
        deleted_at TIMESTAMPTZ
      )
    ''');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_mp_videos_channel ON mp_videos(channel_id)');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_mp_videos_upload ON mp_videos(upload_timestamp DESC)');

    // -------------------------------------------------------------
    // 🚀 CHANNEL SUBSCRIPTIONS TRACKER
    // -------------------------------------------------------------
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_channel_subscriptions (
        subscriber_uid TEXT,
        channel_id TEXT,
        PRIMARY KEY (subscriber_uid, channel_id)
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_video_versions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id UUID NOT NULL REFERENCES mp_videos(id),
        quality TEXT NOT NULL,
        format TEXT DEFAULT 'mp4',
        file_size BIGINT,
        storage_path TEXT NOT NULL,
        transcoded_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE(video_id, quality)
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_upload_queue (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id UUID REFERENCES mp_videos(id),
        status TEXT DEFAULT 'pending',
        progress_percent DECIMAL DEFAULT 0,
        error_log TEXT,
        retry_count INTEGER DEFAULT 0,
        max_retries INTEGER DEFAULT 5,
        started_at TIMESTAMPTZ DEFAULT NOW(),
        completed_at TIMESTAMPTZ
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_sticker_products_catalog (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id UUID NOT NULL REFERENCES mp_videos(id),
        product_id TEXT NOT NULL UNIQUE,
        timestamp_in_video DECIMAL NOT NULL,
        clickable_zone JSONB,
        product_name TEXT NOT NULL,
        price DECIMAL,
        currency TEXT DEFAULT 'USD',
        description TEXT,
        link_url TEXT,
        image_path TEXT,
        stock_status TEXT DEFAULT 'in_stock',
        sales_count_local INTEGER DEFAULT 0,
        click_count_local INTEGER DEFAULT 0,
        purchase_initiated_count INTEGER DEFAULT 0,
        purchase_completed_count INTEGER DEFAULT 0,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_sticker_services_catalog (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id UUID NOT NULL REFERENCES mp_videos(id),
        service_id TEXT NOT NULL UNIQUE,
        timestamp_in_video DECIMAL NOT NULL,
        clickable_zone JSONB,
        service_name TEXT NOT NULL,
        price DECIMAL,
        currency TEXT DEFAULT 'USD',
        description TEXT,
        availability_slots JSONB DEFAULT '[]',
        booking_count_local INTEGER DEFAULT 0,
        is_active BOOLEAN DEFAULT TRUE,
        trustme_message_template TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_playlists (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        channel_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        is_public BOOLEAN DEFAULT TRUE,
        cover_image_path TEXT,
        video_count INTEGER DEFAULT 0,
        total_duration_seconds INTEGER DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_playlist_videos (
        playlist_id UUID NOT NULL REFERENCES mp_playlists(id),
        video_id UUID NOT NULL REFERENCES mp_videos(id),
        position INTEGER NOT NULL DEFAULT 0,
        added_at TIMESTAMPTZ DEFAULT NOW(),
        PRIMARY KEY (playlist_id, video_id)
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_draft_videos (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        channel_id TEXT NOT NULL,
        title TEXT,
        description TEXT,
        tags TEXT[] DEFAULT '{}',
        file_path_temp TEXT,
        thumbnail_temp_path TEXT,
        last_edited_at TIMESTAMPTZ DEFAULT NOW(),
        schedule_publish_at TIMESTAMPTZ,
        cross_post_platforms TEXT[] DEFAULT '{}',
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_cross_post_status (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id TEXT NOT NULL,
        platform TEXT NOT NULL,
        post_type TEXT,
        platform_post_id TEXT,
        status TEXT DEFAULT 'pending',
        error_message TEXT,
        published_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_watch_history (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id TEXT NOT NULL,
        creator_channel_id TEXT NOT NULL,
        creator_uid TEXT,
        watch_timestamp TIMESTAMPTZ DEFAULT NOW(),
        watch_duration_seconds INTEGER DEFAULT 0,
        percent_completed DECIMAL DEFAULT 0,
        device_type TEXT DEFAULT 'desktop',
        paused_count INTEGER DEFAULT 0,
        rewind_count INTEGER DEFAULT 0,
        speed_changes INTEGER DEFAULT 0,
        quality_watched TEXT DEFAULT 'auto',
        completed BOOLEAN DEFAULT FALSE,
        session_id TEXT NOT NULL,
        is_incognito BOOLEAN DEFAULT FALSE
      )
    ''');
    await conn.execute('CREATE INDEX IF NOT EXISTS idx_mp_watch_history_video ON mp_watch_history(video_id)');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_watch_history_tags (
        history_id UUID NOT NULL REFERENCES mp_watch_history(id),
        tag TEXT NOT NULL,
        weight DECIMAL DEFAULT 1.0,
        PRIMARY KEY (history_id, tag)
      )
    ''');


    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_liked_videos (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id TEXT NOT NULL,
        creator_uid TEXT,
        liked_timestamp TIMESTAMPTZ DEFAULT NOW(),
        reaction_type TEXT NOT NULL DEFAULT 'heart',
        is_incognito BOOLEAN DEFAULT FALSE
      )
    ''');

    // -------------------------------------------------------------
      // 🚀 THE GATEKEEPER: Unique Video Views Tracker
      // Prevents the same user from spamming views on a single video
      // -------------------------------------------------------------
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS mp_viewed_videos (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          video_id TEXT NOT NULL,
          viewer_uid TEXT NOT NULL,
          viewed_at TIMESTAMPTZ DEFAULT NOW(),
          UNIQUE(video_id, viewer_uid) -- This forces 1 view per person!
        )
      ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_commented_videos (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id TEXT NOT NULL,
        creator_uid TEXT,
        comment_text TEXT NOT NULL,
        comment_timestamp TIMESTAMPTZ DEFAULT NOW(),
        parent_comment_id UUID,
        likes_on_comment_local INTEGER DEFAULT 0,
        reaction_heart INTEGER DEFAULT 0,
        reaction_laugh INTEGER DEFAULT 0,
        reaction_agree INTEGER DEFAULT 0,
        reaction_disagree INTEGER DEFAULT 0,
        routed_to_trustme BOOLEAN DEFAULT FALSE,
        is_incognito BOOLEAN DEFAULT FALSE
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_saved_videos (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id TEXT NOT NULL,
        creator_uid TEXT,
        saved_timestamp TIMESTAMPTZ DEFAULT NOW(),
        folder_name TEXT DEFAULT 'Default',
        is_incognito BOOLEAN DEFAULT FALSE
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_shared_videos (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id TEXT NOT NULL,
        creator_uid TEXT,
        shared_timestamp TIMESTAMPTZ DEFAULT NOW(),
        share_method TEXT DEFAULT 'link',
        share_timestamp_in_video DECIMAL,
        recipient_uids TEXT[] DEFAULT '{}',
        opened_by_receiver BOOLEAN DEFAULT FALSE,
        is_incognito BOOLEAN DEFAULT FALSE
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_recommendation_profile (
        user_id UUID PRIMARY KEY,
        top_categories JSONB DEFAULT '{}',
        top_tags JSONB DEFAULT '{}',
        preferred_languages TEXT[] DEFAULT '{en}',
        location_bias TEXT,
        time_of_day_patterns JSONB DEFAULT '{}',
        ollama_embedding_vector DECIMAL[],
        last_ollama_training_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS mp_live_stream_sessions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        video_id TEXT NOT NULL UNIQUE,
        channel_id TEXT NOT NULL,
        webrtc_offer TEXT,
        webrtc_candidates JSONB DEFAULT '[]',
        viewer_count INTEGER DEFAULT 0,
        started_at TIMESTAMPTZ DEFAULT NOW(),
        ended_at TIMESTAMPTZ,
        total_watch_time_seconds INTEGER DEFAULT 0,
        total_messages INTEGER DEFAULT 0,
        total_gifts INTEGER DEFAULT 0,
        is_active BOOLEAN DEFAULT TRUE
      )
    ''');

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS tm_call_log (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        call_id TEXT NOT NULL UNIQUE,
        contact_guptik_id TEXT NOT NULL,
        contact_username TEXT,
        call_type TEXT NOT NULL DEFAULT 'video',
        direction TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'ringing',
        sdp_offer TEXT,
        sdp_answer TEXT,
        ice_candidates JSONB DEFAULT '[]',
        webrtc_session_state TEXT,
        started_at TIMESTAMPTZ,
        answered_at TIMESTAMPTZ,
        ended_at TIMESTAMPTZ,
        duration_seconds INTEGER DEFAULT 0,
        call_quality TEXT DEFAULT 'good',
        is_muted_local BOOLEAN DEFAULT FALSE,
        is_video_off_local BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    ''');

    // Reaction Trigger (Creator Side Aggregation)
    await conn.execute('''
      CREATE OR REPLACE FUNCTION update_reaction_counts()
      RETURNS TRIGGER AS \$\$
      BEGIN
          UPDATE mp_videos SET
              reaction_heart_count = (SELECT COUNT(*) FROM mp_liked_videos WHERE video_id = NEW.video_id AND reaction_type = 'heart'),
              reaction_fire_count = (SELECT COUNT(*) FROM mp_liked_videos WHERE video_id = NEW.video_id AND reaction_type = 'fire'),
              reaction_thumbs_up_count = (SELECT COUNT(*) FROM mp_liked_videos WHERE video_id = NEW.video_id AND reaction_type = 'thumbs_up'),
              reaction_clap_count = (SELECT COUNT(*) FROM mp_liked_videos WHERE video_id = NEW.video_id AND reaction_type = 'clap'),
              reaction_laugh_count = (SELECT COUNT(*) FROM mp_liked_videos WHERE video_id = NEW.video_id AND reaction_type = 'laugh'),
              reaction_surprised_count = (SELECT COUNT(*) FROM mp_liked_videos WHERE video_id = NEW.video_id AND reaction_type = 'surprised'),
              reaction_sad_count = (SELECT COUNT(*) FROM mp_liked_videos WHERE video_id = NEW.video_id AND reaction_type = 'sad')
          WHERE id = NEW.video_id::UUID;
          RETURN NEW;
      END;
      \$\$ LANGUAGE plpgsql
    ''');

  }

  // ==============================================================================
  // SECTION 3: VAULT METHODS
  // ==============================================================================

  Future<String?> createShareSettings({
    required String fileName,
    required bool isPublic,
    List<String> emails = const [],
    DateTime? expiresAt,
  }) async {
    if (_connection == null || !_connection!.isOpen) await connect();

    final token = isPublic ? null : _generateSecureToken();

    await _connection!.execute(
      Sql.named('''
        INSERT INTO vault_share_file 
        (file_name, emails_access_to, access_token, is_public, expires_at) 
        VALUES (@fn, @emails::TEXT[], @token, @pub, @exp)
      '''),
      parameters: {
        'fn': fileName,
        'emails': emails.isEmpty ? null : emails,
        'token': token,
        'pub': isPublic,
        'exp': expiresAt?.toUtc(),
      },
    );

    return token;
  }

  Future<void> saveVaultFileLocal({
    required String fileName,
    required String filePath,
    required int fileSize,
    required String mimeType,
  }) async {
    if (_connection == null || !_connection!.isOpen) await connect();
    if (_connection == null || !_connection!.isOpen) {
      throw Exception("DATABASE OFFLINE: Could not connect to Postgres!");
    }

    print("DEBUG: Attempting to insert $fileName into database...");

    await _connection!.execute(
      Sql.named(
        'INSERT INTO vault_files (file_name, file_path, file_size, mime_type) VALUES (@fn, @fp, @fs, @mt)',
      ),
      parameters: {
        'fn': fileName,
        'fp': filePath,
        'fs': fileSize,
        'mt': mimeType,
      },
    );

    print("DEBUG: Successfully inserted $fileName into Postgres!");
  }

  // ==============================================================================
  // SECTION 4: OLLAMA AI METHODS
  // ==============================================================================

  Future<void> saveChatMessage({
    required String sessionId,
    required String role,
    required String content,
    required String model,
  }) async {
    if (!_isConnected) return;
    final safeContent = content.replaceAll("'", "''");

    await _connection!.execute('''
      INSERT INTO ollama_chat_memory (session_id, role, content, model_used)
      VALUES ('$sessionId', '$role', '$safeContent', '$model')
    ''');
  }

  Future<List<Map<String, dynamic>>> getChatHistory(String sessionId) async {
    if (!_isConnected) return [];

    final result = await _connection!.execute('''
      SELECT role, content, created_at 
      FROM ollama_chat_memory 
      WHERE session_id = '$sessionId' 
      ORDER BY created_at ASC
    ''');

    return result.map((row) {
      return {
        'role': row[0] as String,
        'content': row[1] as String,
        'created_at': row[2].toString(),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getChatSessions() async {
    if (!_isConnected) return [];

    final result = await _connection!.execute('''
      SELECT DISTINCT ON (session_id) 
        session_id, 
        content, 
        created_at
      FROM ollama_chat_memory
      WHERE role = 'user'
      ORDER BY session_id, created_at ASC
    ''');

    final List<Map<String, dynamic>> sessions = result.map((row) {
      String snippet = (row[1] as String);
      if (snippet.length > 30) snippet = "${snippet.substring(0, 30)}...";

      return {
        'id': row[0] as String,
        'title': snippet,
        'date': row[2].toString(),
      };
    }).toList();

    sessions.sort((a, b) => b['date'].compareTo(a['date']));
    return sessions;
  }

  Future<void> initOllamaTableUpdates() async {
    if (!_isConnected) return;
    try {
      await _connection!.execute(
        'ALTER TABLE ollama_models ADD COLUMN IF NOT EXISTS system_prompt TEXT',
      );
    } catch (_) {}
  }

  Future<void> saveOllamaModel(String modelTag) async {
    if (!_isConnected) return;
    await initOllamaTableUpdates();
    await _connection!.execute('''
      INSERT INTO ollama_models (model_tag, is_active)
      VALUES ('$modelTag', TRUE)
      ON CONFLICT (model_tag) DO NOTHING;
    ''');
  }

  Future<void> updateModelPrompt(String modelTag, String prompt) async {
    if (!_isConnected) return;
    final safePrompt = prompt.replaceAll("'", "''");
    await _connection!.execute('''
      UPDATE ollama_models SET system_prompt = '$safePrompt' WHERE model_tag = '$modelTag'
    ''');
  }

  Future<void> deleteOllamaModelDb(String modelTag) async {
    if (!_isConnected) return;
    await _connection!.execute(
      "DELETE FROM ollama_models WHERE model_tag = '$modelTag'",
    );
  }

  Future<List<Map<String, dynamic>>> getSavedModels() async {
    if (!_isConnected) return [];
    await initOllamaTableUpdates();
    final result = await _connection!.execute(
      'SELECT model_tag, system_prompt FROM ollama_models',
    );

    return result
        .map(
          (r) => {
            'model_tag': r[0].toString(),
            'system_prompt': r[1]?.toString() ?? '',
          },
        )
        .toList();
  }

  // ==============================================================================
  // SECTION 5: 🚀 TRUST ME CRYPTO METHODS (V1 ENTERPRISE)
  // ==============================================================================

  /// Checks if the node already has a Cryptographic Identity generated
  Future<bool> hasTrustIdentity() async {
    if (_connection == null || !_connection!.isOpen) await connect();
    final result = await _connection!.execute(
      'SELECT 1 FROM tm_identity LIMIT 1',
    );
    return result.isNotEmpty;
  }

  /// Locks the generated Signal-Protocol Key Bundle directly into Postgres.
  /// Called by the Desktop UI (`TrustMeScreen`) on first boot.
  Future<void> saveTrustIdentity({
    required String guptikId,
    required String username,
    required Map<String, dynamic> keyBundle,
    required String deviceFingerprint,
  }) async {
    if (_connection == null || !_connection!.isOpen) await connect();

    try {
      print("🔐 Injecting Cryptographic Identity into local Postgres...");

      // Encode the JSON array of one-time pre-keys so Postgres JSONB accepts it
      final oneTimeKeysJson = jsonEncode(keyBundle['one_time_prekeys']);

      await _connection!.execute(
        Sql.named('''
          INSERT INTO tm_identity (
            guptik_user_id, 
            username, 
            identity_public_key, 
            identity_private_key_enc, 
            signed_prekey_public, 
            signed_prekey_private_enc, 
            signed_prekey_signature,
            one_time_prekeys,
            one_time_prekeys_count,
            device_fingerprint,
            device_type
          ) VALUES (
            @gid, @user, @idPub, 'stored_in_secure_enclave', @spkPub, 'stored_in_secure_enclave', @spkSig, @otpk::jsonb, @otpkCount, @device, 'desktop'
          )
        '''),
        parameters: {
          'gid': guptikId,
          'user': username,
          'idPub': keyBundle['identity_public_key'],
          'spkPub': keyBundle['signed_prekey_public'],
          'spkSig': keyBundle['signed_prekey_signature'],
          'otpk': oneTimeKeysJson,
          'otpkCount': (keyBundle['one_time_prekeys'] as List).length,
          'device': deviceFingerprint,
        },
      );

      print("✅ Identity securely saved to database!");
    } catch (e) {
      print("❌ Error saving Trust Identity: $e");
      rethrow;
    }
  }

  // ==============================================================================
  // SECTION 6: UTILITY / SCHEMA VIEWING
  // ==============================================================================

  Future<List<Map<String, dynamic>>> getTableSchema(String tableName) async {
    if (!_isConnected) return [];
    try {
      final result = await _connection!.execute('''
        SELECT column_name, data_type, column_default, is_nullable
        FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = '$tableName'
        ORDER BY ordinal_position;
      ''');
      return result
          .map(
            (row) => {
              'name': row[0].toString(),
              'type': row[1].toString(),
              'default': row[2]?.toString(),
              'nullable': row[3].toString() == 'YES',
            },
          )
          .toList();
    } catch (e) {
      print("Schema Fetch Error: $e");
      return [];
    }
  }

  Future<List<String>> getTableNames() async {
    if (!_isConnected) return [];
    try {
      final result = await _connection!.execute('''
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_type = 'BASE TABLE';
      ''');
      return result.map((row) => row[0].toString()).toList();
    } catch (e) {
      print("Error fetching tables: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTableData(String tableName) async {
    if (!_isConnected) return [];
    try {
      final result = await _connection!.execute('SELECT * FROM "$tableName"');
      return result.map((row) => row.toColumnMap()).toList();
    } catch (e) {
      print("Error fetching table data: $e");
      return [];
    }
  }

  Future<List<String>> getTableColumns(String tableName) async {
    if (!_isConnected) return [];
    try {
      final result = await _connection!.execute('''
        SELECT column_name FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = '$tableName';
      ''');
      return result.map((row) => row[0].toString()).toList();
    } catch (e) {
      print("Error fetching columns: $e");
      return [];
    }
  }

  Future<void> executeRawQuery(String query) async {
    if (!_isConnected) return;
    try {
      await _connection!.execute(query);
    } catch (e) {
      print("Error executing query: $e");
      rethrow;
    }
  }
}