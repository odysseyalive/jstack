// At the very top of the file
import dotenv from 'dotenv';
dotenv.config();

// supabase-cloud-to-selfhosted-migration.js
import { createClient } from '@supabase/supabase-js';
import pg from 'pg';
import fs from 'fs/promises';
import path from 'path';
import fetch from 'node-fetch';

class SupabaseCloudToSelfHostedMigrator {
  constructor(sourceConfig, targetConfig) {
    this.sourceConfig = sourceConfig;
    this.targetConfig = targetConfig;

    // Initialize Supabase client for source (cloud)
    this.sourceClient = createClient(sourceConfig.url, sourceConfig.anonKey);

    // Initialize Supabase client for target (self-hosted) if URL provided
    if (targetConfig.url && targetConfig.anonKey) {
      this.targetClient = createClient(targetConfig.url, targetConfig.anonKey);
    }

    // Initialize direct PostgreSQL connections
    this.sourcePool = new pg.Pool({
      connectionString: sourceConfig.dbUrl,
    });

    // Target uses direct PostgreSQL connection (typical for self-hosted)
    this.targetPool = new pg.Pool({
      connectionString: targetConfig.dbUrl,
    });
  }

  async testConnections() {
    console.log('Testing connections...');

    try {
      // Test source connection
      const sourceTest = await this.sourcePool.query('SELECT version()');
      console.log('✓ Source (Cloud) database connected');
      console.log(`  PostgreSQL ${sourceTest.rows[0].version.split(' ')[1]}`);

      // Test target connection
      const targetTest = await this.targetPool.query('SELECT version()');
      console.log('✓ Target (Self-hosted) database connected');
      console.log(`  PostgreSQL ${targetTest.rows[0].version.split(' ')[1]}`);

      // Check if target has Supabase extensions
      const extensions = await this.targetPool.query(`
        SELECT extname FROM pg_extension 
        WHERE extname IN ('pgsodium', 'pg_graphql', 'pg_stat_statements', 'pgcrypto', 'pgjwt', 'uuid-ossp')
        ORDER BY extname;
      `);

      if (extensions.rows.length > 0) {
        console.log('✓ Target has Supabase extensions installed:');
        extensions.rows.forEach(ext => console.log(`  - ${ext.extname}`));
      } else {
        console.log('⚠ Warning: No Supabase extensions detected in target database');
        console.log('  Some functionality may not work without proper extensions');
      }

      return true;
    } catch (error) {
      console.error('Connection test failed:', error.message);
      return false;
    }
  }

  async cleanTargetSchema(forceClean = false) {
    if (!forceClean) {
      console.log('\n🧹 Skipping schema cleanup (use --clean to drop existing tables)');
      return;
    }

    console.log('\n⚠️  WARNING: Cleaning target schema (dropping existing tables)...');
    console.log('   This will DELETE all existing data in the public schema!');

    try {
      // Get all objects to drop
      const tables = await this.targetPool.query(`
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
      `);

      const views = await this.targetPool.query(`
        SELECT viewname FROM pg_views WHERE schemaname = 'public'
      `);

      const sequences = await this.targetPool.query(`
        SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
      `);

      const types = await this.targetPool.query(`
        SELECT typname FROM pg_type t 
        JOIN pg_namespace n ON n.oid = t.typnamespace 
        WHERE n.nspname = 'public' AND t.typtype IN ('e', 'c', 'd')
      `);

      const functions = await this.targetPool.query(`
        SELECT proname, oidvectortypes(proargtypes) as argtypes 
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
      `);

      // Drop all tables with CASCADE
      for (const table of tables.rows) {
        try {
          await this.targetPool.query(`DROP TABLE IF EXISTS public."${table.tablename}" CASCADE`);
          console.log(`  ✓ Dropped table: ${table.tablename}`);
        } catch (err) {
          console.log(`  ⚠ Could not drop table ${table.tablename}: ${err.message}`);
        }
      }

      // Drop all views
      for (const view of views.rows) {
        try {
          await this.targetPool.query(`DROP VIEW IF EXISTS public."${view.viewname}" CASCADE`);
          console.log(`  ✓ Dropped view: ${view.viewname}`);
        } catch (err) {
          console.log(`  ⚠ Could not drop view ${view.viewname}: ${err.message}`);
        }
      }

      // Drop all sequences
      for (const seq of sequences.rows) {
        try {
          await this.targetPool.query(`DROP SEQUENCE IF EXISTS public."${seq.sequencename}" CASCADE`);
          console.log(`  ✓ Dropped sequence: ${seq.sequencename}`);
        } catch (err) {
          console.log(`  ⚠ Could not drop sequence ${seq.sequencename}: ${err.message}`);
        }
      }

      // Drop all custom types
      for (const type of types.rows) {
        try {
          await this.targetPool.query(`DROP TYPE IF EXISTS public."${type.typname}" CASCADE`);
          console.log(`  ✓ Dropped type: ${type.typname}`);
        } catch (err) {
          console.log(`  ⚠ Could not drop type ${type.typname}: ${err.message}`);
        }
      }

      // Drop all functions
      for (const func of functions.rows) {
        try {
          await this.targetPool.query(`DROP FUNCTION IF EXISTS public."${func.proname}"(${func.argtypes}) CASCADE`);
          console.log(`  ✓ Dropped function: ${func.proname}`);
        } catch (err) {
          // Functions might have multiple overloads, so this is expected sometimes
          // Silent fail on functions
        }
      }

      console.log('  ✓ Target schema cleaned successfully');

    } catch (error) {
      console.error('  ✗ Failed to clean target schema:', error.message);
      throw error;
    }
  }

  async migrateSchema() {
    console.log('\n📋 Starting schema migration...\n');

    try {
      // Check if we should clean the target first
      const shouldClean = process.argv.includes('--clean');
      if (shouldClean) {
        await this.cleanTargetSchema(true);
      }

      // Step 1: Extract schema information
      const schemaInfo = await this.extractSchema();

      // Step 2: Prepare target database
      await this.prepareTargetDatabase();

      // Step 3: Generate DDL statements
      const ddlStatements = await this.generateDDL(schemaInfo);

      // Step 4: Execute DDL on target database
      await this.executeDDL(ddlStatements);

      // Step 5: Migrate RLS policies
      await this.migrateRLSPolicies();

      // Step 6: Migrate database functions
      await this.migrateFunctions();

      // Step 7: Migrate triggers
      await this.migrateTriggers();

      // Step 8: Set up auth schema if needed
      await this.setupAuthSchema();

      console.log('\n✅ Schema migration completed successfully!');
    } catch (error) {
      console.error('Migration failed:', error);
      throw error;
    }
  }

  async prepareTargetDatabase() {
    console.log('Preparing target database...');

    // Create necessary schemas if they don't exist
    const schemas = ['public', 'auth', 'storage', 'extensions'];

    for (const schema of schemas) {
      try {
        await this.targetPool.query(`CREATE SCHEMA IF NOT EXISTS ${schema};`);
        console.log(`  ✓ Schema '${schema}' ready`);
      } catch (error) {
        console.log(`  ℹ Schema '${schema}' already exists or cannot be created`);
      }
    }

    // Ensure required extensions are installed
    const requiredExtensions = [
      'uuid-ossp',
      'pgcrypto',
      'pgjwt',
      'pg_stat_statements',
      'pg_trgm',  // Add this for text search
      'vector'    // Add this for vector operations if available
    ];

    for (const ext of requiredExtensions) {
      try {
        await this.targetPool.query(`CREATE EXTENSION IF NOT EXISTS "${ext}";`);
        console.log(`  ✓ Extension '${ext}' ready`);
      } catch (error) {
        console.log(`  ⚠ Could not create extension '${ext}':`, error.message);
      }
    }
  }

  async extractSchema() {
    const schemaInfo = {
      tables: [],
      views: [],
      types: [],
      extensions: [],
      sequences: []
    };

    // Define system schemas to exclude
    const systemSchemas = ['pg_catalog', 'information_schema', 'pg_toast', 'auth', 'storage',
      'extensions', 'supabase_functions', 'supabase_migrations',
      'realtime', 'vault', 'net', 'cron', 'graphql', 'graphql_public', 'pgsodium'];

    // Get all sequences first (we need these before creating tables)
    // Also get sequences that might not exist yet but are referenced
    const sequencesQuery = `
      SELECT 
        schemaname,
        sequencename,
        coalesce(start_value, 1) as start_value,
        coalesce(increment_by, 1) as increment_by,
        max_value,
        min_value,
        coalesce(cache_size, 1) as cache_size,
        coalesce(cycle, false) as cycle
      FROM pg_sequences
      WHERE schemaname NOT IN (${systemSchemas.map(s => `'${s}'`).join(',')});
    `;
    const sequences = await this.sourcePool.query(sequencesQuery);
    schemaInfo.sequences = sequences.rows;

    // Also check for sequences referenced in defaults but not existing
    const missingSequencesQuery = `
      SELECT DISTINCT 
        'public' as schemaname,
        regexp_replace(column_default, '.*nextval\\(''([^'']+)''.*', '\\1') as sequencename
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND column_default LIKE '%nextval(%'
        AND regexp_replace(column_default, '.*nextval\\(''([^'']+)''.*', '\\1') NOT IN (
          SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
        );
    `;

    try {
      const missingSeqs = await this.sourcePool.query(missingSequencesQuery);
      // Add missing sequences with default values
      for (const seq of missingSeqs.rows) {
        if (seq.sequencename && !seq.sequencename.includes('::')) {
          schemaInfo.sequences.push({
            schemaname: 'public',
            sequencename: seq.sequencename.replace(/^public\./, '').replace(/::.*$/, ''),
            start_value: 1,
            increment_by: 1,
            max_value: null,
            min_value: null,
            cache_size: 1,
            cycle: false
          });
        }
      }
    } catch (e) {
      console.log('  Could not check for missing sequences:', e.message);
    }

    // Get all extensions (excluding common ones)
    const extensionsQuery = `
      SELECT extname 
      FROM pg_extension 
      WHERE extname NOT IN ('plpgsql', 'pgcrypto', 'uuid-ossp', 'pgjwt', 'pg_stat_statements');
    `;
    const extensions = await this.sourcePool.query(extensionsQuery);
    schemaInfo.extensions = extensions.rows;

    // Get all custom types - only from public schema to avoid permission issues
    const typesQuery = `
      SELECT 
        n.nspname as schema,
        t.typname as name,
        t.typtype as type,
        CASE 
          WHEN t.typtype = 'e' THEN 
            array_to_string(ARRAY(
              SELECT e.enumlabel
              FROM pg_enum e
              WHERE e.enumtypid = t.oid
              ORDER BY e.enumsortorder
            ), ',')
          ELSE NULL
        END as enum_values
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname = 'public'  -- Only public schema to avoid permission issues
        AND t.typtype IN ('e', 'c', 'd')
      ORDER BY t.typname;
    `;
    const types = await this.sourcePool.query(typesQuery);
    schemaInfo.types = types.rows;

    // Get all tables with their structure - only from public schema
    const tablesQuery = `
      SELECT 
        schemaname,
        tablename
      FROM pg_tables
      WHERE schemaname = 'public'  -- Only public schema to avoid permission issues
        AND tablename NOT LIKE 'pg_%'
      ORDER BY schemaname, tablename;
    `;

    const tables = await this.sourcePool.query(tablesQuery);

    for (const table of tables.rows) {
      const tableInfo = await this.getTableStructure(table.schemaname, table.tablename);
      schemaInfo.tables.push(tableInfo);
    }

    // Get all views - only from public schema
    const viewsQuery = `
      SELECT 
        schemaname,
        viewname,
        definition
      FROM pg_views
      WHERE schemaname = 'public'  -- Only public schema to avoid permission issues
      ORDER BY schemaname, viewname;
    `;
    const views = await this.sourcePool.query(viewsQuery);
    schemaInfo.views = views.rows;

    return schemaInfo;
  }

  async getTableStructure(schema, tableName) {
    // Get columns
    const columnsQuery = `
      SELECT 
        column_name,
        data_type,
        character_maximum_length,
        numeric_precision,
        numeric_scale,
        is_nullable,
        column_default,
        udt_name
      FROM information_schema.columns
      WHERE table_schema = $1 AND table_name = $2
      ORDER BY ordinal_position;
    `;
    const columns = await this.sourcePool.query(columnsQuery, [schema, tableName]);

    // Get constraints
    const constraintsQuery = `
      SELECT 
        conname as constraint_name,
        contype as constraint_type,
        pg_get_constraintdef(c.oid) as definition
      FROM pg_constraint c
      JOIN pg_namespace n ON n.oid = c.connamespace
      JOIN pg_class cls ON cls.oid = c.conrelid
      WHERE n.nspname = $1 AND cls.relname = $2;
    `;
    const constraints = await this.sourcePool.query(constraintsQuery, [schema, tableName]);

    // Get indexes
    const indexesQuery = `
      SELECT 
        indexname,
        indexdef
      FROM pg_indexes
      WHERE schemaname = $1 AND tablename = $2
      AND indexname NOT IN (
        SELECT conname 
        FROM pg_constraint 
        WHERE contype IN ('p', 'u')
      );
    `;
    const indexes = await this.sourcePool.query(indexesQuery, [schema, tableName]);

    return {
      schema,
      name: tableName,
      columns: columns.rows,
      constraints: constraints.rows,
      indexes: indexes.rows
    };
  }

  async generateDDL(schemaInfo) {
    const ddlStatements = [];

    // Create extensions (that aren't standard Supabase ones)
    for (const ext of schemaInfo.extensions) {
      ddlStatements.push(`CREATE EXTENSION IF NOT EXISTS ${ext.extname};`);
    }

    // Create sequences first (before tables that reference them)
    for (const seq of schemaInfo.sequences) {
      const maxVal = seq.max_value ? seq.max_value : '9223372036854775807';
      const minVal = seq.min_value ? seq.min_value : '1';
      ddlStatements.push(`
        CREATE SEQUENCE IF NOT EXISTS ${seq.schemaname}.${seq.sequencename}
        START WITH ${seq.start_value}
        INCREMENT BY ${seq.increment_by}
        MINVALUE ${minVal}
        MAXVALUE ${maxVal}
        CACHE ${seq.cache_size}
        ${seq.cycle ? 'CYCLE' : 'NO CYCLE'};
      `);
    }

    // Create custom types
    for (const type of schemaInfo.types) {
      if (type.type === 'e') { // Enum type
        const values = type.enum_values.split(',').map(v => `'${v}'`).join(', ');
        ddlStatements.push(`
          DO $$ BEGIN
            CREATE TYPE ${type.schema}.${type.name} AS ENUM (${values});
          EXCEPTION
            WHEN duplicate_object THEN null;
          END $$;
        `);
      }
    }

    // Create tables without foreign key constraints first
    for (const table of schemaInfo.tables) {
      let createTableSQL = `CREATE TABLE IF NOT EXISTS ${table.schema}.${table.name} (\n`;

      // Add columns
      const columnDefs = table.columns.map(col => {
        let def = `  ${col.column_name} ${this.getColumnType(col)}`;
        if (col.is_nullable === 'NO') def += ' NOT NULL';
        if (col.column_default) def += ` DEFAULT ${col.column_default}`;
        return def;
      });

      createTableSQL += columnDefs.join(',\n');

      // Add primary key constraint inline if exists
      const pkConstraint = table.constraints.find(c => c.constraint_type === 'p');
      if (pkConstraint) {
        createTableSQL += `,\n  CONSTRAINT ${pkConstraint.constraint_name} ${pkConstraint.definition}`;
      }

      // Add unique constraints inline if exists
      const uniqueConstraints = table.constraints.filter(c => c.constraint_type === 'u');
      for (const constraint of uniqueConstraints) {
        createTableSQL += `,\n  CONSTRAINT ${constraint.constraint_name} ${constraint.definition}`;
      }

      createTableSQL += '\n);';
      ddlStatements.push(createTableSQL);
    }

    // Add foreign key constraints after all tables are created
    for (const table of schemaInfo.tables) {
      for (const constraint of table.constraints) {
        if (constraint.constraint_type === 'f') { // Foreign key
          ddlStatements.push(`
            ALTER TABLE ${table.schema}.${table.name}
            ADD CONSTRAINT ${constraint.constraint_name} ${constraint.definition};
          `);
        }
      }
    }

    // Add indexes after tables exist
    for (const table of schemaInfo.tables) {
      for (const index of table.indexes) {
        ddlStatements.push(index.indexdef + ';');
      }
    }

    // Create views last (may depend on tables)
    for (const view of schemaInfo.views) {
      ddlStatements.push(`
        CREATE OR REPLACE VIEW ${view.schemaname}.${view.viewname} AS
        ${view.definition}
      `);
    }

    return ddlStatements;
  }

  getColumnType(col) {
    let type = col.data_type;

    // Handle ARRAY types
    if (col.data_type === 'ARRAY') {
      // PostgreSQL internal array naming convention
      if (col.udt_name && col.udt_name.startsWith('_')) {
        type = col.udt_name.substring(1) + '[]';
      } else {
        // Default to text array
        type = 'text[]';
      }
    } else if (col.data_type === 'character varying' && col.character_maximum_length) {
      type = `varchar(${col.character_maximum_length})`;
    } else if (col.data_type === 'numeric' && col.numeric_precision) {
      type = `numeric(${col.numeric_precision}${col.numeric_scale ? ',' + col.numeric_scale : ''})`;
    } else if (col.data_type === 'USER-DEFINED') {
      type = col.udt_name;
    }

    return type;
  }

  async executeDDL(statements) {
    console.log(`\n📝 Executing ${statements.length} DDL statements...`);

    let successCount = 0;
    let failCount = 0;

    for (const statement of statements) {
      try {
        await this.targetPool.query(statement);
        successCount++;
        process.stdout.write('.');
      } catch (error) {
        failCount++;
        console.error(`\n✗ Statement failed: ${error.message}`);
        console.error('Statement:', statement.substring(0, 100) + '...');
      }
    }

    console.log(`\n  ✓ ${successCount} statements executed successfully`);
    if (failCount > 0) {
      console.log(`  ✗ ${failCount} statements failed`);
    }
  }

  async migrateRLSPolicies() {
    console.log('\n🔒 Migrating RLS policies...');

    // Only migrate policies for public schema to avoid permission issues
    const policiesQuery = `
      SELECT 
        schemaname,
        tablename,
        policyname,
        permissive,
        roles,
        cmd,
        qual,
        with_check
      FROM pg_policies
      WHERE schemaname = 'public';
    `;

    const policies = await this.sourcePool.query(policiesQuery);

    if (policies.rows.length === 0) {
      console.log('  No RLS policies to migrate');
      return;
    }

    for (const policy of policies.rows) {
      try {
        // First, enable RLS on the table
        await this.targetPool.query(`
          ALTER TABLE ${policy.schemaname}.${policy.tablename} ENABLE ROW LEVEL SECURITY;
        `);

        // Create the policy
        let policySQL = `CREATE POLICY ${policy.policyname} ON ${policy.schemaname}.${policy.tablename}`;
        policySQL += ` AS ${policy.permissive}`;
        policySQL += ` FOR ${policy.cmd}`;
        policySQL += ` TO ${policy.roles.join(', ')}`;
        if (policy.qual) policySQL += ` USING (${policy.qual})`;
        if (policy.with_check) policySQL += ` WITH CHECK (${policy.with_check})`;
        policySQL += ';';

        await this.targetPool.query(policySQL);
        console.log(`  ✓ Policy ${policy.policyname} migrated`);
      } catch (error) {
        console.error(`  ✗ Failed to migrate policy ${policy.policyname}:`, error.message);
      }
    }
  }

  async migrateFunctions() {
    console.log('\n⚙️ Migrating database functions...');

    // Only migrate functions from public schema that use SQL/PLPGSQL languages
    // Skip C language functions as they're from extensions
    const functionsQuery = `
      SELECT 
        n.nspname as schema_name,
        p.proname as function_name,
        pg_get_functiondef(p.oid) as definition,
        l.lanname as language
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_language l ON l.oid = p.prolang
      WHERE n.nspname = 'public'  -- Only public schema
        AND p.prokind = 'f'
        AND l.lanname IN ('sql', 'plpgsql')  -- Skip C language functions
      ORDER BY p.proname;
    `;

    const functions = await this.sourcePool.query(functionsQuery);

    if (functions.rows.length === 0) {
      console.log('  No custom functions to migrate');
      return;
    }

    console.log(`  Found ${functions.rows.length} SQL/PLPGSQL functions to migrate`);

    for (const func of functions.rows) {
      try {
        await this.targetPool.query(func.definition);
        console.log(`  ✓ Function ${func.function_name} migrated`);
      } catch (error) {
        console.error(`  ✗ Failed to migrate function ${func.function_name}:`, error.message);
      }
    }
  }

  async migrateTriggers() {
    console.log('\n🎯 Migrating triggers...');

    // Only migrate triggers from public schema to avoid permission issues
    const triggersQuery = `
      SELECT 
        trigger_schema,
        trigger_name,
        event_manipulation,
        event_object_schema,
        event_object_table,
        action_statement,
        action_orientation,
        action_timing
      FROM information_schema.triggers
      WHERE trigger_schema = 'public';  -- Only public schema
    `;

    const triggers = await this.sourcePool.query(triggersQuery);

    if (triggers.rows.length === 0) {
      console.log('  No custom triggers to migrate');
      return;
    }

    for (const trigger of triggers.rows) {
      const triggerDef = `
        CREATE TRIGGER ${trigger.trigger_name}
        ${trigger.action_timing} ${trigger.event_manipulation}
        ON ${trigger.event_object_schema}.${trigger.event_object_table}
        FOR EACH ${trigger.action_orientation}
        ${trigger.action_statement};
      `;

      try {
        await this.targetPool.query(triggerDef);
        console.log(`  ✓ Trigger ${trigger.trigger_name} migrated`);
      } catch (error) {
        console.error(`  ✗ Failed to migrate trigger ${trigger.trigger_name}:`, error.message);
      }
    }
  }

  async setupAuthSchema() {
    console.log('\n🔐 Setting up auth schema...');

    // Check if auth.users exists in source
    const authCheck = await this.sourcePool.query(`
      SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'auth' AND table_name = 'users'
      );
    `);

    if (!authCheck.rows[0].exists) {
      console.log('  No auth schema to migrate from source');
      return;
    }

    // Check if target has auth.users
    const targetAuthCheck = await this.targetPool.query(`
      SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'auth' AND table_name = 'users'
      );
    `);

    if (!targetAuthCheck.rows[0].exists) {
      console.log('  ⚠ Target doesn\'t have auth.users table');
      console.log('    Auth tables are typically created by Supabase during installation');
      console.log('    You may need to run the Supabase auth migration scripts manually');
    } else {
      console.log('  ✓ Auth schema already exists in target');
    }
  }

  async downloadEdgeFunctionsFromCloud() {
    console.log('\n📥 Downloading Edge Functions from Supabase Cloud...');

    const managementToken = this.sourceConfig.managementApiToken;
    const projectRef = this.sourceConfig.projectRef;

    if (!managementToken) {
      console.log('  ⚠ No SOURCE_MANAGEMENT_API_TOKEN provided');
      console.log('    Create one at: https://supabase.com/dashboard/account/tokens');
      console.log('    Add to .env: SOURCE_MANAGEMENT_API_TOKEN=sbp_...');
      return null;
    }

    if (!projectRef) {
      console.log('  ⚠ No SOURCE_PROJECT_REF provided');
      console.log('    Add to .env: SOURCE_PROJECT_REF=your-project-ref');
      return null;
    }

    try {
      // List all functions
      console.log(`  Fetching functions list for project: ${projectRef}`);
      const listResponse = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/functions`, {
        headers: {
          'Authorization': `Bearer ${managementToken}`,
          'Content-Type': 'application/json'
        }
      });

      if (!listResponse.ok) {
        const errorText = await listResponse.text();
        throw new Error(`Failed to list functions: ${listResponse.status} - ${errorText}`);
      }

      const functions = await listResponse.json();

      if (!functions || functions.length === 0) {
        console.log('  No Edge Functions found in Supabase Cloud project');
        return null;
      }

      console.log(`  Found ${functions.length} Edge Functions:`);
      functions.forEach(func => {
        console.log(`    - ${func.slug} (v${func.version}, ${func.status})`);
      });

      // Create temporary directory for downloaded functions
      const downloadPath = './migration-temp-functions';
      await fs.mkdir(downloadPath, { recursive: true });

      const downloadedFunctions = [];

      // Download each function's body
      for (const func of functions) {
        console.log(`\n  Downloading: ${func.slug}`);

        try {
          const bodyResponse = await fetch(
            `https://api.supabase.com/v1/projects/${projectRef}/functions/${func.slug}/body`,
            {
              headers: {
                'Authorization': `Bearer ${managementToken}`,
              }
            }
          );

          if (!bodyResponse.ok) {
            throw new Error(`Failed to download: ${bodyResponse.status}`);
          }

          // The response is an eszip (Deno's binary module format)
          const buffer = await bodyResponse.arrayBuffer();
          const eszipPath = path.join(downloadPath, `${func.slug}.eszip`);
          await fs.writeFile(eszipPath, Buffer.from(buffer));

          console.log(`    ✓ Downloaded ${func.slug}.eszip`);

          // Extract TypeScript source from eszip
          const extractPath = path.join(downloadPath, func.slug);
          await fs.mkdir(extractPath, { recursive: true });

          try {
            // Read eszip file and extract TypeScript source
            const eszipBuffer = await fs.readFile(eszipPath);
            const content = eszipBuffer.toString('utf-8', 0, Math.min(eszipBuffer.length, 1024 * 1024));

            // Find source/index.ts marker
            const sourceMarker = 'source/index.ts';
            const sourceIndex = content.indexOf(sourceMarker);

            if (sourceIndex === -1) {
              throw new Error('Could not find index.ts source marker');
            }

            // Extract code after marker
            const afterMarker = content.substring(sourceIndex + sourceMarker.length);

            // Find start of TypeScript code
            const codePatterns = [/import\s+.*from/, /Deno\.serve\(/, /export\s+/, /const\s+\w+\s*=/, /function\s+\w+/];
            let codeStart = -1;
            for (const pattern of codePatterns) {
              const match = afterMarker.search(pattern);
              if (match !== -1 && (codeStart === -1 || match < codeStart)) {
                codeStart = match;
              }
            }

            if (codeStart === -1) {
              throw new Error('Could not find TypeScript code start');
            }

            let code = afterMarker.substring(codeStart);

            // Find end of code
            const endPatterns = [/\x00{4,}/, /_file:\/\//, /ESZIP/];
            let codeEnd = code.length;
            for (const pattern of endPatterns) {
              const match = code.search(pattern);
              if (match !== -1 && match < codeEnd) {
                codeEnd = match;
              }
            }

            code = code.substring(0, codeEnd);

            // Clean up binary artifacts
            code = code
              .split('\n')
              .filter(line => {
                const printable = line.replace(/[^\x20-\x7E\n\r\t]/g, '').length;
                const total = line.length;
                return total === 0 || (printable / total) > 0.5;
              })
              .join('\n')
              .trim();

            // Write index.ts
            const indexPath = path.join(extractPath, 'index.ts');
            await fs.writeFile(indexPath, code, 'utf-8');

            console.log(`    ✓ Extracted ${code.length} bytes to ${extractPath}`);

            // Clean up eszip file
            await fs.unlink(eszipPath);

            downloadedFunctions.push({
              name: func.slug,
              path: extractPath,
              metadata: func
            });

          } catch (extractError) {
            console.log(`    ✗ Failed to extract: ${extractError.message}`);
            console.log(`    ℹ Keeping eszip file at: ${eszipPath}`);
          }

        } catch (error) {
          console.log(`    ✗ Failed to download ${func.slug}: ${error.message}`);
        }
      }

      console.log(`\n  ✓ Downloaded ${downloadedFunctions.length} of ${functions.length} functions`);

      return {
        functions: downloadedFunctions,
        downloadPath: downloadPath
      };

    } catch (error) {
      console.error('  ✗ Failed to download Edge Functions:', error.message);
      return null;
    }
  }

  async migrateEdgeFunctions() {
    console.log('\n🚀 Migrating Edge Functions...');

    const jstackPath = this.targetConfig.jstackPath || process.env.JSTACK_PATH || '/home/jarvis/jstack';
    let functionsPath = this.sourceConfig.edgeFunctionsPath || './supabase/functions';
    let downloadResult = null;
    let cleanupDownloads = false;

    // First, try to download from Supabase Cloud
    if (this.sourceConfig.managementApiToken && this.sourceConfig.projectRef) {
      downloadResult = await this.downloadEdgeFunctionsFromCloud();

      if (downloadResult && downloadResult.functions.length > 0) {
        // Use the downloaded functions
        functionsPath = downloadResult.downloadPath;
        cleanupDownloads = true;
        console.log(`\n  Using downloaded functions from: ${functionsPath}`);
      }
    } else {
      console.log('\n  ⚠ Skipping cloud download (no Management API token or project ref)');
      console.log('    Will use local files from:', functionsPath);
    }

    try {
      // Get list of function directories
      let functionDirs;

      if (downloadResult) {
        // Use downloaded functions list
        functionDirs = downloadResult.functions.map(f => ({
          name: f.name,
          isDirectory: () => true
        }));
      } else {
        // Use local files
        const entries = await fs.readdir(functionsPath, { withFileTypes: true });
        // Filter out system directories (_main, _shared, etc)
        functionDirs = entries.filter(entry =>
          entry.isDirectory() && !entry.name.startsWith('_')
        );
      }

      if (functionDirs.length === 0) {
        console.log('  No Edge Functions found to migrate');
        return;
      }

      console.log(`\n  Found ${functionDirs.length} Edge Functions to migrate`);
      console.log(`  JStack path: ${jstackPath}`);

      // Check if JStack exists
      const jstackScript = path.join(jstackPath, 'jstack.sh');
      try {
        await fs.access(jstackScript);
      } catch (error) {
        console.log('  ⚠ JStack script not found, falling back to simple file copy');
        return this.migrateEdgeFunctionsFallback(functionsPath, functionDirs);
      }

      console.log('\n  Using JStack to import edge functions...\n');

      // Import each function using JStack
      const { exec } = await import('child_process');
      const { promisify } = await import('util');
      const execAsync = promisify(exec);

      for (const dir of functionDirs) {
        const functionName = dir.name;
        const sourceFunctionPath = path.resolve(functionsPath, functionName);

        console.log(`  Importing function: ${functionName}`);

        try {
          // Use JStack import command with absolute paths
          const scriptPath = path.join(jstackPath, 'scripts/core/manage_edge_functions.sh');

          // Use yes command to auto-answer prompts (overwrite existing functions)
          const importCmd = `cd ${jstackPath} && yes y 2>/dev/null | bash "${scriptPath}" import "${sourceFunctionPath}" 2>&1 || true`;

          const { stdout, stderr } = await execAsync(importCmd, {
            shell: '/bin/bash',
            timeout: 30000
          });

          if (stdout) {
            console.log(`    ✓ Imported successfully`);
            // Show any important output
            if (stdout.includes('Test at:')) {
              const testUrl = stdout.match(/Test at: (.*)/)?.[1];
              if (testUrl) {
                console.log(`    ${testUrl}`);
              }
            }
          }
          if (stderr && !stderr.includes('warning')) {
            console.log(`    ⚠ ${stderr.trim()}`);
          }
        } catch (error) {
          console.log(`    ✗ Import failed: ${error.message}`);
          console.log(`    ℹ You can manually import later with:`);
          console.log(`      cd ${jstackPath} && ./jstack.sh --functions import "${sourceFunctionPath}"`);
        }
      }

      console.log('\n  ✓ Edge Functions migration completed');
      console.log('\n  📌 Next steps:');
      console.log('     1. Register functions in _main router for Docker deployment');
      console.log(`     2. Edit: ${path.join(jstackPath, 'supabase/functions/_main/index.ts')}`);
      console.log('     3. Add each function to REGISTERED_FUNCTIONS array');
      console.log('     4. Add handler case in switch statement');
      console.log('     5. Implement handler function');
      console.log(`     6. Restart: cd ${jstackPath} && ./jstack.sh --functions restart`);
      console.log('\n     Or for local development:');
      console.log(`     cd ${jstackPath} && supabase functions serve`);

      // Clean up downloaded files
      if (cleanupDownloads) {
        console.log('\n  🧹 Cleaning up downloaded files...');
        await fs.rm(functionsPath, { recursive: true, force: true });
        console.log('    ✓ Cleanup complete');
      }

    } catch (error) {
      console.error('  ✗ Failed to migrate Edge Functions:', error.message);
      console.log('    Make sure the source Edge Functions path exists');
      console.log(`    Source path: ${functionsPath}`);
    }
  }

  async migrateEdgeFunctionsFallback(functionsPath, functionDirs) {
    const targetPath = './migrated-edge-functions';

    console.log('\n  Using fallback: copying to temporary directory');
    console.log(`  Target: ${targetPath}`);

    // Create target directory
    await fs.mkdir(targetPath, { recursive: true });

    for (const dir of functionDirs) {
      const functionName = dir.name;
      const sourceFunctionPath = path.join(functionsPath, functionName);
      const targetFunctionPath = path.join(targetPath, functionName);

      console.log(`  Copying: ${functionName}`);
      await this.copyDirectory(sourceFunctionPath, targetFunctionPath);
      console.log(`    ✓ Copied to ${targetFunctionPath}`);
    }

    // Create instructions file
    const instructions = `# Edge Functions Migration Instructions

## Migrated Functions

${functionDirs.map(dir => `- ${dir.name}`).join('\n')}

## Import to JStack

To import these functions into your JStack instance:

\`\`\`bash
# Import each function
${functionDirs.map(dir => `
# Import ${dir.name}
cd /home/jarvis/jstack
./jstack.sh --functions import "$(pwd)/migrated-edge-functions/${dir.name}"
`).join('\n')}
\`\`\`

## Register in Docker

After importing, register each function in the _main router:

1. Edit: \`/home/jarvis/jstack/supabase/functions/_main/index.ts\`
2. Add to REGISTERED_FUNCTIONS array:
   \`\`\`typescript
   const REGISTERED_FUNCTIONS = [
${functionDirs.map(dir => `     '${dir.name}',`).join('\n')}
   ]
   \`\`\`
3. Add handler case in switch statement
4. Implement handler function
5. Restart: \`./jstack.sh --functions restart\`

## Local Development

For development with auto-discovery:

\`\`\`bash
cd /home/jarvis/jstack
supabase functions serve
\`\`\`

Functions will be available at:
${functionDirs.map(dir => `- http://localhost:54321/functions/v1/${dir.name}`).join('\n')}
`;

    await fs.writeFile(path.join(targetPath, 'IMPORT_INSTRUCTIONS.md'), instructions);

    console.log(`\n  ✓ Functions copied to: ${targetPath}`);
    console.log('  ✓ See IMPORT_INSTRUCTIONS.md for next steps');
  }

  async copyDirectory(source, target) {
    await fs.mkdir(target, { recursive: true });
    const entries = await fs.readdir(source, { withFileTypes: true });

    for (const entry of entries) {
      const sourcePath = path.join(source, entry.name);
      const targetPath = path.join(target, entry.name);

      if (entry.isDirectory()) {
        await this.copyDirectory(sourcePath, targetPath);
      } else {
        await fs.copyFile(sourcePath, targetPath);
      }
    }
  }

  async migrateStorageBuckets() {
    console.log('\n📦 Migrating Storage Buckets configuration...');

    if (!this.sourceClient) {
      console.log('  ⚠ Source client not configured, skipping storage migration');
      return;
    }

    try {
      // List buckets from source
      const { data: buckets, error } = await this.sourceClient.storage.listBuckets();

      if (error) {
        console.error('  Failed to list storage buckets:', error);
        return;
      }

      if (!buckets || buckets.length === 0) {
        console.log('  No storage buckets to migrate');
        return;
      }

      // Save bucket configuration for manual setup
      const bucketConfig = {
        buckets: buckets.map(bucket => ({
          name: bucket.name,
          public: bucket.public,
          allowed_mime_types: bucket.allowed_mime_types,
          file_size_limit: bucket.file_size_limit
        }))
      };

      const configPath = './storage-buckets-config.json';
      await fs.writeFile(configPath, JSON.stringify(bucketConfig, null, 2));

      console.log(`  ✓ Bucket configuration saved to ${configPath}`);
      console.log(`  📌 Found ${buckets.length} buckets:`);
      buckets.forEach(bucket => {
        console.log(`     - ${bucket.name} (${bucket.public ? 'public' : 'private'})`);
      });

      // If target client is available, try to create buckets
      if (this.targetClient) {
        for (const bucket of buckets) {
          try {
            const { error: createError } = await this.targetClient.storage.createBucket(
              bucket.name,
              {
                public: bucket.public,
                allowedMimeTypes: bucket.allowed_mime_types,
                fileSizeLimit: bucket.file_size_limit
              }
            );

            if (createError) {
              if (createError.message.includes('already exists')) {
                console.log(`     ✓ Bucket ${bucket.name} already exists`);
              } else {
                console.error(`     ✗ Failed to create bucket ${bucket.name}:`, createError.message);
              }
            } else {
              console.log(`     ✓ Bucket ${bucket.name} created`);
            }
          } catch (error) {
            console.log(`     ℹ Could not create bucket ${bucket.name} - may need manual setup`);
          }
        }
      } else {
        console.log('\n  📌 To create buckets in self-hosted Supabase:');
        console.log('     1. Access your self-hosted Supabase dashboard');
        console.log('     2. Navigate to Storage section');
        console.log('     3. Create buckets using the configuration in storage-buckets-config.json');
      }

    } catch (error) {
      console.error('  Storage migration failed:', error);
    }
  }

  async migrateData(includeData = false, newTelegramId = null) {
    if (!includeData) {
      console.log('\n📊 Skipping data migration (use --include-data to migrate data)');
      return;
    }

    console.log('\n📊 Migrating data...');

    if (newTelegramId) {
      console.log(`  🔄 Will replace ALL values in user_telegram_id and chat_telegram_id columns with: ${newTelegramId}`);
    }

    // Get all tables with their foreign key dependencies
    const tablesQuery = `
      SELECT schemaname, tablename
      FROM pg_tables
      WHERE schemaname = 'public'  -- Only public schema
      ORDER BY tablename;
    `;

    const tables = await this.sourcePool.query(tablesQuery);

    // Get foreign key dependencies
    const fkQuery = `
      SELECT
        tc.table_name,
        ccu.table_name AS foreign_table_name
      FROM information_schema.table_constraints AS tc
      JOIN information_schema.key_column_usage AS kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage AS ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema = 'public';
    `;

    const fkResult = await this.sourcePool.query(fkQuery);

    // Build dependency map
    const dependencies = {};
    fkResult.rows.forEach(row => {
      if (!dependencies[row.table_name]) {
        dependencies[row.table_name] = [];
      }
      dependencies[row.table_name].push(row.foreign_table_name);
    });

    // Topological sort to determine correct migration order
    const sortedTables = this.topologicalSort(tables.rows.map(t => t.tablename), dependencies);

    console.log(`  📋 Migrating ${sortedTables.length} tables in dependency order\n`);

    for (const tablename of sortedTables) {
      const tableName = `public.${tablename}`;
      console.log(`  Migrating data for ${tableName}...`);

      try {
        // Get row count
        const countResult = await this.sourcePool.query(`SELECT COUNT(*) FROM ${tableName}`);
        const totalRows = parseInt(countResult.rows[0].count);

        if (totalRows === 0) {
          console.log(`    No data to migrate`);
          continue;
        }

        console.log(`    Found ${totalRows} rows`);

        // Check if table exists in target
        const tableExists = await this.targetPool.query(`
          SELECT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = $1 AND table_name = $2
          )
        `, ['public', tablename]);

        if (!tableExists.rows[0].exists) {
          console.log(`    ✗ Table doesn't exist in target, skipping`);
          continue;
        }

        // Get column information from target to handle type conversions
        const targetColumns = await this.targetPool.query(`
          SELECT column_name, data_type, udt_name
          FROM information_schema.columns
          WHERE table_schema = $1 AND table_name = $2
          ORDER BY ordinal_position
        `, ['public', tablename]);

        const columnTypeMap = {};
        targetColumns.rows.forEach(col => {
          columnTypeMap[col.column_name] = {
            type: col.data_type,
            udt: col.udt_name
          };
        });

        // Disable triggers temporarily for faster insertion
        // Use session_replication_role to bypass triggers without needing superuser
        await this.targetPool.query(`SET session_replication_role = replica;`);

        // Use COPY for efficient data transfer
        const sourceData = await this.sourcePool.query(`SELECT * FROM ${tableName}`);

        if (sourceData.rows.length > 0) {
          const columns = Object.keys(sourceData.rows[0]);

          // Check which telegram columns exist in this table
          const telegramIdColumns = columns.filter(col =>
            col === 'user_telegram_id' || col === 'chat_telegram_id'
          );

          // Insert in batches to avoid query size limits
          const batchSize = 100;
          let insertedCount = 0;

          for (let i = 0; i < sourceData.rows.length; i += batchSize) {
            const batch = sourceData.rows.slice(i, i + batchSize);

            const values = batch.map(row => {
              // Replace ALL telegram IDs if specified (including null values)
              if (newTelegramId && telegramIdColumns.length > 0) {
                for (const col of telegramIdColumns) {
                  const colType = columnTypeMap[col];

                  // Replace with new ID regardless of current value (including nulls)
                  // Handle different column types
                  if (colType && colType.type === 'bigint') {
                    row[col] = BigInt(newTelegramId);
                  } else {
                    // For text/varchar columns
                    row[col] = newTelegramId;
                  }
                }
              }

              return `(${columns.map(col => {
                if (row[col] === null) return 'NULL';

                // Handle different data types
                const colType = columnTypeMap[col];

                if (colType && colType.type === 'timestamp with time zone') {
                  // Handle timestamp columns
                  if (typeof row[col] === 'object') {
                    // If it's a JSON object, extract the timestamp value
                    const timestamp = row[col].timestamp || row[col].value || row[col];
                    return `'${new Date(timestamp).toISOString()}'::timestamptz`;
                  }
                  return `'${row[col]}'::timestamptz`;
                } else if (colType && colType.type === 'ARRAY') {
                  // Handle array columns (text[], int[], etc.)
                  if (Array.isArray(row[col])) {
                    const arrayElements = row[col].map(item => {
                      if (item === null) return 'NULL';
                      return `'${String(item).replace(/'/g, "''")}'`;
                    }).join(',');
                    return `ARRAY[${arrayElements}]::${colType.udt}`;
                  }
                  return 'NULL';
                } else if (typeof row[col] === 'object') {
                  // Handle JSON/JSONB columns (not arrays)
                  if (Array.isArray(row[col])) {
                    // This shouldn't happen with proper type detection above, but handle it
                    return `'${JSON.stringify(row[col]).replace(/'/g, "''")}'::jsonb`;
                  }
                  return `'${JSON.stringify(row[col]).replace(/'/g, "''")}'::jsonb`;
                } else if (typeof row[col] === 'boolean') {
                  return row[col] ? 'true' : 'false';
                } else {
                  // Default string handling
                  return `'${String(row[col]).replace(/'/g, "''")}'`;
                }
              }).join(',')})`;
            });

            const insertQuery = `
              INSERT INTO ${tableName} (${columns.join(',')}) 
              VALUES ${values.join(',\n')}
              ON CONFLICT DO NOTHING;
            `;

            await this.targetPool.query(insertQuery);
            insertedCount += batch.length;

            // Show progress
            process.stdout.write(`\r    Progress: ${insertedCount}/${totalRows} rows`);
          }

          console.log(`\n    ✓ ${insertedCount} rows migrated`);
        }

        // Re-enable triggers
        await this.targetPool.query(`SET session_replication_role = default;`);

      } catch (error) {
        console.error(`    ✗ Failed to migrate data for ${tableName}:`, error.message);
        // Try to re-enable triggers even if migration failed
        try {
          await this.targetPool.query(`SET session_replication_role = default;`);
        } catch (e) {
          // Ignore
        }
      }
    }
  }

  topologicalSort(tables, dependencies) {
    // Topological sort using Kahn's algorithm
    const result = [];
    const visited = new Set();
    const inDegree = {};

    // Initialize in-degree for all tables
    tables.forEach(table => {
      inDegree[table] = 0;
    });

    // Calculate in-degrees
    Object.entries(dependencies).forEach(([table, deps]) => {
      deps.forEach(dep => {
        if (tables.includes(dep)) {
          inDegree[table] = (inDegree[table] || 0) + 1;
        }
      });
    });

    // Find all tables with no dependencies
    let queue = tables.filter(table => inDegree[table] === 0);

    while (queue.length > 0) {
      // Sort queue alphabetically for consistent ordering
      queue.sort();
      const current = queue.shift();
      result.push(current);
      visited.add(current);

      // Find tables that depend on current table
      Object.entries(dependencies).forEach(([table, deps]) => {
        if (deps.includes(current) && !visited.has(table)) {
          inDegree[table]--;
          if (inDegree[table] === 0) {
            queue.push(table);
          }
        }
      });
    }

    // If we haven't visited all tables, there's a circular dependency
    // Add remaining tables at the end
    const remaining = tables.filter(t => !visited.has(t));
    if (remaining.length > 0) {
      console.log(`  ⚠ Warning: Circular dependencies detected for: ${remaining.join(', ')}`);
      result.push(...remaining);
    }

    return result;
  }

  async migrateAuthUsers(includeAuth = false) {
    if (!includeAuth) {
      console.log('\n👤 Skipping auth users migration (use --include-auth to migrate auth data)');
      return;
    }

    console.log('\n👤 Migrating auth users...');
    console.log('  ⚠ Note: Passwords cannot be migrated. Users will need to reset passwords.');

    try {
      // Check if source has auth users
      const sourceUsers = await this.sourcePool.query(`
        SELECT id, email, email_confirmed_at, created_at, updated_at, raw_user_meta_data
        FROM auth.users;
      `);

      if (sourceUsers.rows.length === 0) {
        console.log('  No users to migrate');
        return;
      }

      console.log(`  Found ${sourceUsers.rows.length} users to migrate`);

      // Check if target has auth.users table
      const targetAuthCheck = await this.targetPool.query(`
        SELECT EXISTS (
          SELECT 1 FROM information_schema.tables 
          WHERE table_schema = 'auth' AND table_name = 'users'
        );
      `);

      if (!targetAuthCheck.rows[0].exists) {
        console.log('  ✗ Target doesn\'t have auth.users table');
        console.log('    Cannot migrate users without auth schema');
        return;
      }

      // Export users to a file for manual review/import
      const usersExport = {
        exported_at: new Date().toISOString(),
        users: sourceUsers.rows.map(user => ({
          id: user.id,
          email: user.email,
          email_confirmed: user.email_confirmed_at !== null,
          created_at: user.created_at,
          updated_at: user.updated_at,
          metadata: user.raw_user_meta_data
        }))
      };

      await fs.writeFile('auth-users-export.json', JSON.stringify(usersExport, null, 2));
      console.log('  ✓ User data exported to auth-users-export.json');
      console.log('  📌 Users will need to reset their passwords in the new system');

    } catch (error) {
      console.error('  ✗ Failed to migrate auth users:', error.message);
    }
  }

  async generateMigrationReport() {
    const report = {
      timestamp: new Date().toISOString(),
      source: {
        type: 'Supabase Cloud',
        url: this.sourceConfig.url,
        project_ref: this.sourceConfig.projectRef
      },
      target: {
        type: 'Self-hosted Supabase',
        url: this.targetConfig.url || 'Direct PostgreSQL connection',
        database: this.targetConfig.dbUrl.split('/').pop().split('?')[0]
      },
      summary: {
        tables: 0,
        views: 0,
        functions: 0,
        policies: 0,
        triggers: 0
      }
    };

    // Count objects
    const tableCount = await this.sourcePool.query(
      "SELECT COUNT(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'auth', 'storage', 'extensions')"
    );
    report.summary.tables = parseInt(tableCount.rows[0].count);

    const viewCount = await this.sourcePool.query(
      "SELECT COUNT(*) FROM pg_views WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'auth', 'storage', 'extensions')"
    );
    report.summary.views = parseInt(viewCount.rows[0].count);

    const functionCount = await this.sourcePool.query(
      "SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'auth', 'storage', 'extensions', 'pgsodium', 'supabase_functions')"
    );
    report.summary.functions = parseInt(functionCount.rows[0].count);

    const policyCount = await this.sourcePool.query(
      "SELECT COUNT(*) FROM pg_policies WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'auth', 'storage', 'extensions')"
    );
    report.summary.policies = parseInt(policyCount.rows[0].count);

    const triggerCount = await this.sourcePool.query(
      "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema NOT IN ('pg_catalog', 'information_schema', 'auth', 'storage', 'extensions', 'supabase_functions')"
    );
    report.summary.triggers = parseInt(triggerCount.rows[0].count);

    // Save report
    const reportPath = `migration-report-${Date.now()}.json`;
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2));

    console.log('\n📋 Migration Report');
    console.log('==================');
    console.log(`Source: ${report.source.type} (${report.source.url})`);
    console.log(`Target: ${report.target.type} (${report.target.database})`);
    console.log('\nObjects Migrated:');
    console.log(`  Tables: ${report.summary.tables}`);
    console.log(`  Views: ${report.summary.views}`);
    console.log(`  Functions: ${report.summary.functions}`);
    console.log(`  RLS Policies: ${report.summary.policies}`);
    console.log(`  Triggers: ${report.summary.triggers}`);
    console.log(`\nReport saved to: ${reportPath}`);

    return report;
  }

  async close() {
    // Only close pools if they exist and haven't been closed
    if (this.sourcePool && !this.sourcePool.ended) {
      await this.sourcePool.end();
    }
    if (this.targetPool && !this.targetPool.ended) {
      await this.targetPool.end();
    }
  }
}

// Main execution
async function main() {
  console.log('🚀 Supabase Cloud to Self-Hosted Migration Tool\n');
  console.log('================================================\n');

  // Load configuration from environment variables
  const sourceConfig = {
    // Cloud Supabase configuration
    url: process.env.SOURCE_SUPABASE_URL,
    anonKey: process.env.SOURCE_SUPABASE_ANON_KEY,
    serviceKey: process.env.SOURCE_SUPABASE_SERVICE_KEY,
    dbUrl: process.env.SOURCE_DATABASE_URL,
    projectRef: process.env.SOURCE_PROJECT_REF,
    managementApiToken: process.env.SOURCE_MANAGEMENT_API_TOKEN,
    edgeFunctionsPath: process.env.SOURCE_EDGE_FUNCTIONS_PATH || './supabase/functions'
  };

  const targetConfig = {
    // Self-hosted Supabase configuration
    dbUrl: process.env.TARGET_DATABASE_URL, // This is the main requirement
    url: process.env.TARGET_SUPABASE_URL, // Optional: if you have the API running
    anonKey: process.env.TARGET_SUPABASE_ANON_KEY, // Optional: if you have the API running
    serviceKey: process.env.TARGET_SUPABASE_SERVICE_KEY, // Optional
    edgeFunctionsPath: process.env.TARGET_EDGE_FUNCTIONS_PATH || './migrated-edge-functions',
    jstackPath: process.env.JSTACK_PATH || '/home/jarvis/jstack'
  };

  // Check if only migrating functions
  const onlyFunctions = process.argv.includes('--only-functions');

  // Validate minimum required configuration
  if (!onlyFunctions) {
    // For full migration, require database credentials
    if (!sourceConfig.url || !sourceConfig.anonKey || !sourceConfig.dbUrl) {
      console.error('❌ Missing required source configuration');
      console.error('   Required: SOURCE_SUPABASE_URL, SOURCE_SUPABASE_ANON_KEY, SOURCE_DATABASE_URL');
      process.exit(1);
    }

    if (!targetConfig.dbUrl) {
      console.error('❌ Missing required target configuration');
      console.error('   Required: TARGET_DATABASE_URL');
      process.exit(1);
    }
  } else {
    // For functions only, just need source edge functions path
    console.log('📦 Edge Functions Only Mode - Database credentials not required\n');
  }

  const migrator = new SupabaseCloudToSelfHostedMigrator(sourceConfig, targetConfig);

  try {
    // Parse command line arguments
    const includeData = process.argv.includes('--include-data');
    const includeAuth = process.argv.includes('--include-auth');
    const skipSchema = process.argv.includes('--skip-schema');
    const cleanFirst = process.argv.includes('--clean');
    const onlyFunctions = process.argv.includes('--only-functions');

    // Test connections first (skip if only migrating functions)
    if (!onlyFunctions) {
      const connectionsOk = await migrator.testConnections();
      if (!connectionsOk) {
        console.error('\n❌ Could not establish connections. Please check your configuration.');
        process.exit(1);
      }
    }

    // Parse telegram ID replacement
    let newTelegramId = null;
    const replaceTelegramArg = process.argv.find(arg => arg.startsWith('--replace-telegram-id='));
    if (replaceTelegramArg) {
      newTelegramId = replaceTelegramArg.split('=')[1];
      if (newTelegramId) {
        console.log(`\n🔄 Telegram ID replacement configured: ALL user_telegram_id and chat_telegram_id values will be replaced with ${newTelegramId}`);
      } else {
        console.error('❌ Invalid --replace-telegram-id format. Use: --replace-telegram-id=NEW_ID');
        process.exit(1);
      }
    } else if (process.env.NEW_TELEGRAM_ID) {
      newTelegramId = process.env.NEW_TELEGRAM_ID;
      console.log(`\n🔄 Telegram ID replacement from env: ALL user_telegram_id and chat_telegram_id values will be replaced with ${newTelegramId}`);
    }

    // If only migrating functions, skip everything else
    if (onlyFunctions) {
      console.log('\n📦 Edge Functions Only Mode');
      console.log('   Skipping schema, data, storage, and auth migration\n');

      await migrator.migrateEdgeFunctions();

      console.log('\n✅ Edge Functions migration completed!');
      console.log('\n📌 Next steps:');
      console.log('   1. Test functions locally: cd /home/jarvis/jstack && supabase functions serve');
      console.log('   2. Register in _main router for Docker deployment');
      console.log('   3. Restart container: ./jstack.sh --functions restart');

      await migrator.close();
      return;
    }

    // Show warning if using --clean
    if (cleanFirst && !skipSchema) {
      console.log('\n⚠️  WARNING: --clean flag will DROP ALL TABLES in the target public schema!');
      console.log('   This action cannot be undone. Press Ctrl+C within 5 seconds to cancel...\n');
      await new Promise(resolve => setTimeout(resolve, 5000));
    }

    if (!skipSchema) {
      // Step 1: Migrate database schema
      await migrator.migrateSchema();
    }

    // Step 2: Migrate storage buckets configuration
    await migrator.migrateStorageBuckets();

    // Step 3: Migrate Edge Functions
    await migrator.migrateEdgeFunctions();

    // Step 4: Optionally migrate data
    await migrator.migrateData(includeData, newTelegramId);

    // Step 5: Optionally migrate auth users
    await migrator.migrateAuthUsers(includeAuth);

    // Step 6: Generate migration report
    await migrator.generateMigrationReport();

    console.log('\n✅ Migration completed successfully!');
    console.log('\n📌 Next steps for self-hosted deployment:');
    console.log('   1. Review the migration report');
    console.log('   2. Deploy Edge Functions using the instructions in migrated-edge-functions/deploy.sh');
    console.log('   3. Configure storage buckets using storage-buckets-config.json');
    if (includeAuth) {
      console.log('   4. Import auth users from auth-users-export.json');
      console.log('   5. Notify users to reset their passwords');
    }
    console.log('   6. Update your application to use the self-hosted endpoints');
    console.log('   7. Test all functionality thoroughly');

  } catch (error) {
    console.error('\n❌ Migration failed:', error);
    process.exit(1);
  } finally {
    await migrator.close();
  }
}

// Command line help
if (process.argv.includes('--help')) {
  console.log(`
Supabase Cloud to Self-Hosted Migration Tool
============================================

This tool migrates your Supabase Cloud project to a self-hosted Supabase installation.

Usage: node supabase-cloud-to-selfhosted-migration.js [options]

Options:
  --include-data                  Migrate table data (default: schema only)
  --include-auth                  Export auth users (passwords cannot be migrated)
  --skip-schema                   Skip schema migration (only migrate data/functions)
  --clean                         Drop all existing tables before migration
  --only-functions                Migrate ONLY edge functions (skip schema/data/storage/auth)
  --replace-telegram-id=NEW_ID    Replace ALL user_telegram_id and chat_telegram_id values with NEW_ID
  --help                          Show this help message

Required Environment Variables:
  SOURCE_SUPABASE_URL         Supabase Cloud project URL
  SOURCE_SUPABASE_ANON_KEY    Supabase Cloud anonymous key
  SOURCE_DATABASE_URL         Supabase Cloud PostgreSQL connection string
  
  TARGET_DATABASE_URL         Self-hosted PostgreSQL connection string

Optional Environment Variables:
  SOURCE_PROJECT_REF          Supabase Cloud project reference
  SOURCE_SUPABASE_SERVICE_KEY Supabase Cloud service role key
  SOURCE_EDGE_FUNCTIONS_PATH  Path to Edge Functions (default: ./supabase/functions)

  TARGET_SUPABASE_URL         Self-hosted Supabase API URL (if available)
  TARGET_SUPABASE_ANON_KEY   Self-hosted anonymous key (if available)
  TARGET_EDGE_FUNCTIONS_PATH  Where to save Edge Functions fallback (default: ./migrated-edge-functions)
  JSTACK_PATH                 JStack installation path (default: /home/jarvis/jstack)

  NEW_TELEGRAM_ID             New Telegram ID to replace ALL user_telegram_id and chat_telegram_id values

Example .env file:
  # Source (Supabase Cloud)
  SOURCE_SUPABASE_URL=https://xxxxx.supabase.co
  SOURCE_SUPABASE_ANON_KEY=eyJ...
  SOURCE_DATABASE_URL=postgresql://postgres:[password]@db.xxxxx.supabase.co:5432/postgres
  
  # Target (Self-hosted)
  TARGET_DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres
  TARGET_SUPABASE_URL=http://localhost:8000  # Optional
  TARGET_SUPABASE_ANON_KEY=your-self-hosted-anon-key  # Optional

Example usage:
  # Migrate schema only
  node supabase-cloud-to-selfhosted-migration.js

  # Migrate schema and data
  node supabase-cloud-to-selfhosted-migration.js --include-data

  # Migrate ONLY edge functions (skip database)
  node supabase-cloud-to-selfhosted-migration.js --only-functions

  # Migrate everything including auth users export
  node supabase-cloud-to-selfhosted-migration.js --include-data --include-auth

  # Migrate and replace ALL telegram IDs with new ID
  node supabase-cloud-to-selfhosted-migration.js --include-data --replace-telegram-id=987654321

  # Clean and migrate, replacing ALL telegram IDs from environment variable
  export NEW_TELEGRAM_ID=987654321
  node supabase-cloud-to-selfhosted-migration.js --clean --include-data

Notes:
  - Auth user passwords cannot be migrated for security reasons
  - Edge Functions will need manual deployment on self-hosted instance
  - Storage files are not migrated (only bucket configuration)
  - Some Supabase Cloud specific features may not be available in self-hosted
  `);
  process.exit(0);
}

// Run the migration
main().catch(console.error);
