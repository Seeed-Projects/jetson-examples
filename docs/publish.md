# publish

## pypi.org

```sh
# tools update
python3 -m pip install --upgrade build
python3 -m pip install --upgrade twine
```

### Test

```sh
# 1 build
python3 -m build

# 2 publish
python3 -m twine upload --repository testpypi dist/*
### WARNING: do not share you API token !!

# 3 test
pip install -i https://test.pypi.org/simple/ jetson-examples
### make sure version number right
```

### Prod

```sh
# 1 build
python3 -m build

# 2 publish
python3 -m twine upload --repository pypi dist/*
### WARNING: do not share you API token !!

# 3 test
pip install jetson-examples --upgrade
### make sure version number right
```
