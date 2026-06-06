.PHONY: commit push

git_diff = $(shell git diff --name-only --cached | rev | cut -d/ -f 1,2 | rev | xargs)

all:

commit: commit_message ?= $(git_diff)
commit:
	test -n "$(commit_message)"
	git commit -m "$(commit_message)"

push: commit
	git push
