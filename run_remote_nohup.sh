export JEKYLL_ENV=production
nohup bundle exec jekyll server --config ./local/_config.yml --port 4001 >> ../nohup.log &