def topics_arr: [.repositoryTopics[]?.name // empty];
def lang: (.primaryLanguage.name // "none");
def top_langs: ([(.languages // [])[] | {name: .node.name, size}] | sort_by(-.size) | .[0:2] | map(.name));
def name_lc: (.name | ascii_downcase);
def desc_lc: ((.description // "") | ascii_downcase);
def topics_str: (topics_arr | join(",") | ascii_downcase);
def hay: "\(name_lc) \(desc_lc) \(topics_str)";

def category:
  hay as $h |
  lang as $l |
  topics_arr as $t |
  .name as $n |
  if $n == "rping" then "Database"
  elif $n == "orderedmap" then "Utility"
  elif ($h | test("terraform|terraformer|\\btf\\b|tflint|tfstate")) then "Terraform"
  elif ($h | test("kubernetes|k8s|kubectl|helm\\b")) then "Kubernetes"
  elif ($h | test("\\baws\\b|\\bs3\\b|\\bec2\\b|dynamodb|cloudwatch|\\blambda\\b|cloudformation|\\becs\\b|\\brds\\b|\\biam\\b")) then "AWS"
  elif ($h | test("mysql|mariadb")) then "MySQL"
  elif ($h | test("postgres|postgresql|pgsql")) then "PostgreSQL"
  elif ($h | test("redis|memcached|kvs")) then "KVS / Cache"
  elif ($h | test("database|schema|migration|\\bdb\\b|sql\\b")) then "Database"
  elif ($h | test("slack|chatwork|discord|chat-")) then "Chat / Slack"
  elif ($h | test("macos|mac os|osx|alfred|spotlight|applescript|menubar")) or ($l == "Swift") then "macOS / iOS"
  elif ($h | test("docker|container|oci\\b|image-")) then "Docker / Container"
  elif ($h | test("github|git-|ghq|pull request|\\bpr\\b")) then "Git / GitHub"
  elif ($h | test("compression|\\blzf\\b|\\blzo\\b|quicklz|fastlz|libtar|\\btar\\b|\\bgzip\\b|deflate|zlib")) then "Compression"
  elif ($h | test("\\bemail\\b|\\bsmtp\\b|\\bimap\\b|\\bmime\\b|\\bmail\\b|ripmime")) then "Email"
  elif ($h | test("benchmark|perf|load test|stress|profil")) then "Benchmark / Perf"
  elif ($h | test("dns\\b|route53|domain|nameserver|networking|\\btcp\\b|keepalive")) then "DNS / Network"
  elif ($h | test("authentication|oauth|\\bauth\\b|login|credential|crypt|tls|ssl|cert|password|secret")) then "Auth / Security"
  elif ($h | test("log\\b|logging|fluentd|fluent-bit|syslog")) then "Logging"
  elif ($h | test("monitor|metric|prometheus|datadog|new relic|nagios|mackerel")) then "Monitoring"
  elif ($h | test("html|css|web\\b|browser|chrome-extension|safari-extension|browser-extension")) then "Web / Browser"
  elif ($h | test("cli\\b|command-line|command line")) then "CLI"
  elif ($n | endswith("-ruby")) or ($n | startswith("ruby-")) then "Ruby gem"
  elif $l == "Ruby" then "Ruby gem"
  elif $l == "Go" then "Go tool"
  elif $l == "Rust" then "Rust tool"
  elif $l == "Elixir" then "Elixir"
  elif $l == "C" then "C"
  elif $l == "TypeScript" or $l == "JavaScript" then "JS / TS"
  else "Other"
  end;

[ .[] | {
    name,
    url,
    description: (.description // ""),
    categories: [category],
    language: lang,
    languages: top_langs,
    stars: .stargazerCount,
    updated: (.pushedAt | split("T")[0]),
    created: (.createdAt | split("T")[0]),
    topics: topics_arr,
    include: ((.name != "pt") and ((.name | startswith("homebrew-")) | not) and ((.name | endswith(".github.io")) | not) and (.stargazerCount >= 3 or (topics_arr | length) > 0 or ((.description // "") | length) > 10))
} ]
