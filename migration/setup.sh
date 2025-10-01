#!/bin/bash
# Supabase Migration Setup Script

set -e

echo "🚀 Setting up Supabase Migration Tool"
echo "======================================"
echo ""

# Check if we're in the right directory
if [ ! -f "supabase-migration-script.js" ]; then
    echo "❌ Error: supabase-migration-script.js not found"
    echo "   Please run this script from the migration directory"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is not installed"
    echo "   Please install Node.js first: https://nodejs.org/"
    exit 1
fi

echo "✓ Node.js version: $(node --version)"
echo ""

# Initialize npm if package.json doesn't exist
if [ ! -f "package.json" ]; then
    echo "📦 Initializing npm project..."
    npm init -y
    npm pkg set type=module
    echo "✓ package.json created"
else
    echo "✓ package.json already exists"
    # Ensure type is set to module
    npm pkg set type=module
fi
echo ""

# Install dependencies
echo "📦 Installing dependencies..."
npm install @supabase/supabase-js pg dotenv node-fetch
echo "✓ Dependencies installed"
echo ""

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo "📝 Creating .env file from template..."
        cp .env.example .env
        echo "✓ .env file created from .env.example"
    else
        echo "📝 Creating .env file..."
        cat > .env << 'EOF'
# Source (Supabase Cloud)
SOURCE_SUPABASE_URL=https://xxxxx.supabase.co
SOURCE_SUPABASE_ANON_KEY=your-anon-key-here
SOURCE_DATABASE_URL=postgresql://postgres:password@db.xxxxx.supabase.co:5432/postgres

# Target (Self-hosted)
TARGET_DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres

# Optional: Telegram ID Swap
OLD_TELEGRAM_ID=123456789
NEW_TELEGRAM_ID=987654321
EOF
        echo "✓ .env file created"
    fi
    echo ""
    echo "⚠️  IMPORTANT: Edit .env file with your actual credentials"
    echo "   Run: nano .env"
else
    echo "✓ .env file already exists"
fi
echo ""

# Print next steps
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Edit .env file with your credentials:"
echo "     nano .env"
echo ""
echo "  2. Get your Supabase Cloud credentials:"
echo "     - URL/Keys: https://app.supabase.com → Settings → API"
echo "     - DB URL: https://app.supabase.com → Settings → Database"
echo ""
echo "  3. Run a test migration (schema only):"
echo "     node supabase-migration-script.js"
echo ""
echo "  4. Run full migration with data:"
echo "     node supabase-migration-script.js --clean --include-data"
echo ""
echo "📖 For more help, see README.md"
