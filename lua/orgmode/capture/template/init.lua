local TemplateProperties = require('orgmode.capture.template.template_properties')
local Date = require('orgmode.objects.date')
local utils = require('orgmode.utils')

local expansions = {
  ['%f'] = function()
    return vim.fn.expand('%')
  end,
  ['%F'] = function()
    return vim.fn.expand('%:p')
  end,
  ['%n'] = function()
    return os.getenv('USER')
  end,
  ['%x'] = function()
    return vim.fn.getreg('+')
  end,
  ['%t'] = function()
    return string.format('<%s>', Date.today():to_string())
  end,
  ['%T'] = function()
    return string.format('<%s>', Date.now():to_string())
  end,
  ['%u'] = function()
    return string.format('[%s]', Date.today():to_string())
  end,
  ['%U'] = function()
    return string.format('[%s]', Date.now():to_string())
  end,
  ['%a'] = function()
    return string.format('[[file:%s::%s]]', utils.current_file_path(), vim.api.nvim_win_get_cursor(0)[1])
  end,
}

---@class OrgCaptureTemplate
---@field description string
---@field template string|string[]
---@field target string?
---@field headline string?
---@field properties OrgCaptureTemplateProperties
---@field subtemplates table<string, OrgCaptureTemplate>
local Template = {}

function Template:new(opts)
  opts = opts or {}

  vim.validate({
    description = { opts.description, 'string', true },
    template = { opts.template, { 'string', 'table' }, true },
    target = { opts.target, 'string', true },
    headline = { opts.headline, 'string', true },
    properties = { opts.properties, 'table', true },
    subtemplates = { opts.subtemplates, 'table', true },
  })

  local this = {}
  this.description = opts.description or ''
  this.template = opts.template or ''
  this.target = self:_compile(opts.target or '')
  this.headline = opts.headline
  this.properties = TemplateProperties:new(opts.properties)

  this.subtemplates = {}
  for key, subtemplate in pairs(opts.subtemplates or {}) do
    this.subtemplates[key] = Template:new(subtemplate)
  end

  setmetatable(this, self)
  self.__index = self
  return this
end

function Template:setup()
  local initial_position = vim.fn.search('%?')
  local is_at_end_of_line = vim.fn.search('%?$') > 0
  if initial_position > 0 then
    vim.cmd([[norm!"_c2l]])
    if is_at_end_of_line then
      vim.cmd([[startinsert!]])
    else
      vim.cmd([[norm!l]])
      vim.cmd([[startinsert]])
    end
  end
end

function Template:compile()
  local content = self.template
  if type(content) == 'table' then
    content = table.concat(content, '\n')
  end
  content = self:_compile(content)
  return vim.split(content, '\n', { plain = true })
end

---@param lines string[]
---@return string[]
function Template:apply_properties_to_lines(lines)
  local empty_lines = self.properties.empty_lines

  for _ = 1, empty_lines.before do
    table.insert(lines, 1, '')
  end

  for _ = 1, empty_lines.after do
    table.insert(lines, '')
  end

  return lines
end

---@private
---@param content string
---@return string
function Template:_compile(content)
  content = self:_compile_dates(content)
  content = self:_compile_expansions(content)
  content = self:_compile_expressions(content)
  content = self:_compile_prompts(content)
  return content
end

---@param content string
---@return string
function Template:_compile_expansions(content, found_expansions)
  found_expansions = found_expansions or expansions
  for expansion, compiler in pairs(found_expansions) do
    if content:match(vim.pesc(expansion)) then
      content = content:gsub(vim.pesc(expansion), compiler())
    end
  end
  return content
end

---@param content string
---@return string
function Template:_compile_dates(content)
  for exp in content:gmatch('%%<[^>]*>') do
    content = content:gsub(vim.pesc(exp), os.date(exp:sub(3, -2)))
  end
  return content
end

---@param content string
---@return string
function Template:_compile_prompts(content)
  for exp in content:gmatch('%%%^%b{}') do
    local details = exp:match('%{(.*)%}')
    local parts = vim.split(details, '|')
    local title, default = parts[1], parts[2]
    local response
    if #parts > 2 then
      local completion_items = vim.list_slice(parts, 3, #parts)
      local prompt = string.format('%s [%s]: ', title, default)
      response = vim.fn.OrgmodeInput(prompt, '', function(arg_lead)
        return vim.tbl_filter(function(v)
          return v:match('^' .. vim.pesc(arg_lead))
        end, completion_items)
      end)
    else
      local prompt = default and string.format('%s [%s]:', title, default) or title .. ': '
      response = vim.trim(vim.fn.input({
        prompt = prompt,
        cancelreturn = default or '',
      }))
    end
    if #response == 0 and default then
      response = default
    end
    content = content:gsub(vim.pesc(exp), response)
  end
  return content
end

function Template:_compile_expressions(content)
  for exp in content:gmatch('%%%b()') do
    local snippet = exp:match('%((.*)%)')
    local func = load(snippet)
    ---@diagnostic disable-next-line: param-type-mismatch
    local ok, response = pcall(func)
    if ok then
      content = content:gsub(vim.pesc(exp), response)
    end
  end
  return content
end

return Template
