require 'spec_helper'

def create_label_tree
  @d1 = Label.find_or_create_by_path %w(a1 b1 c1 d1)
  @c1 = @d1.parent
  @b1 = @c1.parent
  @a1 = @b1.parent
  @d2 = Label.find_or_create_by_path %w(a1 b1 c2 d2)
  @c2 = @d2.parent
  @d3 = Label.find_or_create_by_path %w(a2 b2 c3 d3)
  @c3 = @d3.parent
  @b2 = @c3.parent
  @a2 = @b2.parent
  Label.update_all("#{Label._ct.order_column} = id")
end

def create_preorder_tree(suffix = "", &block)
  %w(
    a/l/n/r
    a/l/n/q
    a/l/n/p
    a/l/n/o
    a/l/m
    a/b/h/i/j/k
    a/b/c/d/g
    a/b/c/d/f
    a/b/c/d/e
  ).shuffle.each { |ea| Label.find_or_create_by_path(ea.split('/').collect { |ea| "#{ea}#{suffix}" }) }

  Label.roots.each_with_index do |root, root_idx|
    root.order_value = root_idx
    yield(root) if block_given?
    root.save!
    root.self_and_descendants.each do |ea|
      ea.children.to_a.sort_by(&:name).each_with_index do |ea, idx|
        ea.order_value = idx
        yield(ea) if block_given?
        ea.save!
      end
    end
  end
end

describe Label do

  context "destruction" do
    it "properly destroys descendents created with find_or_create_by_path" do
      c = Label.find_or_create_by_path %w(a b c)
      b = c.parent
      a = c.root
      a.destroy
      Label.exists?(id: [a.id, b.id, c.id]).should be_false
    end

    it "properly destroys descendents created with add_child" do
      a = Label.create(name: 'a')
      b = Label.new(name: 'b')
      a.add_child b
      c = Label.new(name: 'c')
      b.add_child c
      a.destroy
      Label.exists?(a).should be_false
      Label.exists?(b).should be_false
      Label.exists?(c).should be_false
    end

    it "properly destroys descendents created with <<" do
      a = Label.create(name: 'a')
      b = Label.new(name: 'b')
      a.children << b
      c = Label.new(name: 'c')
      b.children << c
      a.destroy
      Label.exists?(a).should be_false
      Label.exists?(b).should be_false
      Label.exists?(c).should be_false
    end
  end

  context "roots" do
    it "sorts alphabetically" do
      expected = (0..10).to_a
      expected.shuffle.each do |ea|
        Label.create! do |l|
          l.name = "root #{ea}"
          l.order_value = ea
        end
      end
      Label.roots.collect { |ea| ea.order_value }.should == expected
    end
  end

  context "Base Label class" do
    it "should find or create by path" do
      # class method:
      c = Label.find_or_create_by_path(%w{grandparent parent child})
      c.ancestry_path.should == %w{grandparent parent child}
      c.name.should == "child"
      c.parent.name.should == "parent"
    end
  end

  context "Parent/child inverse relationships" do
    it "should associate both sides of the parent and child relationships" do
      parent = Label.new(:name => 'parent')
      child = parent.children.build(:name => 'child')
      parent.should be_root
      parent.should_not be_leaf
      child.should_not be_root
      child.should be_leaf
    end
  end

  context "DateLabel" do
    it "should find or create by path" do
      date = DateLabel.find_or_create_by_path(%w{2011 November 23})
      date.ancestry_path.should == %w{2011 November 23}
      date.self_and_ancestors.each { |ea| ea.class.should == DateLabel }
      date.name.should == "23"
      date.parent.name.should == "November"
    end
  end

  context "DirectoryLabel" do
    it "should find or create by path" do
      dir = DirectoryLabel.find_or_create_by_path(%w{grandparent parent child})
      dir.ancestry_path.should == %w{grandparent parent child}
      dir.name.should == "child"
      dir.parent.name.should == "parent"
      dir.parent.parent.name.should == "grandparent"
      dir.root.name.should == "grandparent"
      dir.id.should_not == Label.find_or_create_by_path(%w{grandparent parent child})
      dir.self_and_ancestors.each { |ea| ea.class.should == DirectoryLabel }
    end
  end

  context "Mixed class tree" do
    context "preorder tree" do
      before do
        classes = [Label, DateLabel, DirectoryLabel, EventLabel]
        create_preorder_tree do |ea|
          ea.type = classes[ea.order_value % 4].to_s
        end
      end
      it "finds roots with specific classes" do
        Label.roots.should == Label.where(:name => 'a').to_a
        DirectoryLabel.roots.should be_empty
        EventLabel.roots.should be_empty
      end

      it "all is limited to subclasses" do
        DateLabel.all.map(&:name).should =~ %w(f h l n p)
        DirectoryLabel.all.map(&:name).should =~ %w(g q)
        EventLabel.all.map(&:name).should == %w(r)
      end

      it "returns descendents regardless of subclass" do
        Label.root.descendants.map { |ea| ea.class.to_s }.uniq.should =~
          %w(Label DateLabel DirectoryLabel EventLabel)
      end
    end

    it "supports children << and add_child" do
      a = EventLabel.create!(:name => "a")
      b = DateLabel.new(:name => "b")
      a.children << b
      c = Label.new(:name => "c")
      b.add_child(c)

      a.self_and_descendants.collect do |ea|
        ea.class
      end.should == [EventLabel, DateLabel, Label]

      a.self_and_descendants.collect do |ea|
        ea.name
      end.should == %w(a b c)
    end
  end

  context "find_all_by_generation" do
    before :each do
      create_label_tree
    end

    it "finds roots from the class method" do
      Label.find_all_by_generation(0).to_a.should == [@a1, @a2]
    end

    it "finds roots from themselves" do
      @a1.find_all_by_generation(0).to_a.should == [@a1]
    end

    it "finds itself for non-roots" do
      @b1.find_all_by_generation(0).to_a.should == [@b1]
    end

    it "finds children for roots" do
      Label.find_all_by_generation(1).to_a.should == [@b1, @b2]
    end

    it "finds children" do
      @a1.find_all_by_generation(1).to_a.should == [@b1]
      @b1.find_all_by_generation(1).to_a.should == [@c1, @c2]
    end

    it "finds grandchildren for roots" do
      Label.find_all_by_generation(2).to_a.should == [@c1, @c2, @c3]
    end

    it "finds grandchildren" do
      @a1.find_all_by_generation(2).to_a.should == [@c1, @c2]
      @b1.find_all_by_generation(2).to_a.should == [@d1, @d2]
    end

    it "finds great-grandchildren for roots" do
      Label.find_all_by_generation(3).to_a.should == [@d1, @d2, @d3]
    end
  end

  context "loading through self_and_ scopes" do
    before :each do
      create_label_tree
    end

    it "self_and_descendants should result in one select" do
      count_queries do
        a1_array = @a1.self_and_descendants
        a1_array.collect { |ea| ea.name }.should == %w(a1 b1 c1 c2 d1 d2)
      end.should == 1
    end

    it "self_and_ancestors should result in one select" do
      count_queries do
        d1_array = @d1.self_and_ancestors
        d1_array.collect { |ea| ea.name }.should == %w(d1 c1 b1 a1)
      end.should == 1
    end
  end

  context "deterministically orders with polymorphic siblings" do
    before :each do
      @parent = Label.create!(:name => 'parent')
      @a, @b, @c, @d, @e, @f = ('a'..'f').map { |ea| EventLabel.new(:name => ea) }
      @parent.children << @a
      @a.append_sibling(@b)
      @b.append_sibling(@c)
      @c.append_sibling(@d)
      @parent.append_sibling(@e)
      @e.append_sibling(@f)
    end

    def name_and_order(enum)
      enum.map { |ea| [ea.name, ea.order_value] }
    end

    def children_name_and_order
      name_and_order(@parent.children(reload = true))
    end

    def roots_name_and_order
      name_and_order(Label.roots)
    end

    it 'order_values properly' do
      children_name_and_order.should == [['a', 0], ['b', 1], ['c', 2], ['d', 3]]
    end

    it 'when inserted before' do
      @b.append_sibling(@a)
      children_name_and_order.should == [['b', 0], ['a', 1], ['c', 2], ['d', 3]]
    end

    it 'when inserted after' do
      @a.append_sibling(@c)
      children_name_and_order.should == [['a', 0], ['c', 1], ['b', 2], ['d', 3]]
    end

    it 'when inserted before the first' do
      @a.prepend_sibling(@d)
      children_name_and_order.should == [['d', 0], ['a', 1], ['b', 2], ['c', 3]]
    end

    it 'when inserted after the last' do
      @d.append_sibling(@b)
      children_name_and_order.should == [['a', 0], ['c', 1], ['d', 2], ['b', 3]]
    end

    it 'prepends to root nodes' do
      @parent.prepend_sibling(@f)
      roots_name_and_order.should == [['f', 0], ['parent', 1], ['e', 2]]
    end
  end

  it 'behaves like the readme' do
    root = Label.create(name: 'root')
    a = root.append_child(Label.new(name: 'a'))
    b = Label.create(name: 'b')
    c = Label.create(name: 'c')

    a.append_sibling(b)
    a.self_and_siblings.collect(&:name).should == %w(a b)
    root.reload.children.collect(&:name).should == %w(a b)
    root.children.collect(&:order_value).should == [0, 1]

    a.prepend_sibling(b)
    a.self_and_siblings.collect(&:name).should == %w(b a)
    root.reload.children.collect(&:name).should == %w(b a)
    root.children.collect(&:order_value).should == [0, 1]

    a.append_sibling(c)
    a.self_and_siblings.collect(&:name).should == %w(b a c)
    root.reload.children.collect(&:name).should == %w(b a c)
    root.children.collect(&:order_value).should == [0, 1, 2]

    # We need to reload b because it was updated by a.append_sibling(c)
    b.reload.append_sibling(c)
    root.reload.children.collect(&:name).should == %w(b c a)
    root.children.collect(&:order_value).should == [0, 1, 2]

    # We need to reload a because it was updated by b.append_sibling(c)
    d = a.reload.append_sibling(Label.new(:name => "d"))
    d.self_and_siblings.collect(&:name).should == %w(b c a d)
    d.self_and_siblings.collect(&:order_value).should == [0, 1, 2, 3]
  end

  # https://github.com/mceachen/closure_tree/issues/84
  it "properly appends children with <<" do
    root = Label.create(:name => "root")
    a = Label.create(:name => "a", :parent => root)
    b = Label.create(:name => "b", :parent => root)
    a.order_value.should == 0
    b.order_value.should == 1
    #c = Label.create(:name => "c")

    # should the order_value for roots be set?
    root.order_value.should_not be_nil
    root.order_value.should == 0

    # order_value should never be nil on a child.
    a.order_value.should_not be_nil
    a.order_value.should == 0
    # Add a child to root at end of children.
    root.children << b
    b.parent.should == root
    a.self_and_siblings.collect(&:name).should == %w(a b)
    root.reload.children.collect(&:name).should == %w(a b)
    root.children.collect(&:order_value).should == [0, 1]
  end

  context "#add_sibling" do
    it "should move a node before another node which has an uninitialized order_value" do
      f = Label.find_or_create_by_path %w(a b c d e fa)
      f0 = f.prepend_sibling(Label.new(:name => "fb")) # < not alpha sort, so name shouldn't matter
      f0.ancestry_path.should == %w(a b c d e fb)
      f.siblings_before.to_a.should == [f0]
      f0.siblings_before.should be_empty
      f0.siblings_after.should == [f]
      f.siblings_after.should be_empty
      f0.self_and_siblings.should == [f0, f]
      f.self_and_siblings.should == [f0, f]
    end

    let(:f1) { Label.find_or_create_by_path %w(a1 b1 c1 d1 e1 f1) }

    it "should move a node to another tree" do
      f2 = Label.find_or_create_by_path %w(a2 b2 c2 d2 e2 f2)
      f1.add_sibling(f2)
      f2.ancestry_path.should == %w(a1 b1 c1 d1 e1 f2)
      f1.parent.reload.children.should == [f1, f2]
    end

    it "should reorder old-parent siblings when a node moves to another tree" do
      f2 = Label.find_or_create_by_path %w(a2 b2 c2 d2 e2 f2)
      f3 = f2.prepend_sibling(Label.new(:name => "f3"))
      f4 = f2.append_sibling(Label.new(:name => "f4"))
      f1.add_sibling(f2)
      f1.self_and_siblings.collect(&:order_value).should == [0, 1]
      f3.self_and_siblings.collect(&:order_value).should == [0, 1]
      f1.self_and_siblings.collect(&:name).should == %w(f1 f2)
      f3.self_and_siblings.collect(&:name).should == %w(f3 f4)
    end
  end

  context "order_value must be set" do

    before do
      @root = Label.create(name: 'root')
      @a, @b, @c = %w(a b c).map { |n| @root.children.create(name: n) }
    end

    it 'should set order_value on roots' do
      @root.order_value.should == 0
    end

    it 'should set order_value with siblings' do
      @a.order_value.should == 0
      @b.order_value.should == 1
      @c.order_value.should == 2
    end

    it 'should reset order_value when a node is moved to another location' do
      root2 = Label.create(name: 'root2')
      root2.add_child @b
      @a.order_value.should == 0
      @b.order_value.should == 0
      @c.reload.order_value.should == 1
    end
  end

  context "destructive reordering" do
    before :each do
      # to make sure order_value isn't affected by additional nodes:
      create_preorder_tree
      @root = Label.create(:name => 'root')
      @a = @root.children.create!(:name => 'a')
      @b = @a.append_sibling(Label.new(:name => 'b'))
      @c = @b.append_sibling(Label.new(:name => 'c'))
    end
    context "doesn't create sort order gaps" do
      it 'from head' do
        @a.destroy
        @root.reload.children.should == [@b, @c]
        @root.children.map { |ea| ea.order_value }.should == [0, 1]
      end
      it 'from mid' do
        @b.destroy
        @root.reload.children.should == [@a, @c]
        @root.children.map { |ea| ea.order_value }.should == [0, 1]
      end
      it 'from tail' do
        @c.destroy
        @root.reload.children.should == [@a, @b]
        @root.children.map { |ea| ea.order_value }.should == [0, 1]
      end
    end

    context 'add_sibling moves descendant nodes' do
      let(:roots) { (0..10).map { |ea| Label.create(name: ea) } }
      let(:first_root) { roots.first }
      let(:last_root) { roots.last }
      it 'should retain sort orders of descendants when moving to a new parent' do
        expected_order = ('a'..'z').to_a.shuffle
        expected_order.map { |ea| first_root.add_child(Label.new(name: ea)) }
        actual_order = first_root.children(reload = true).pluck(:name)
        actual_order.should == expected_order
        last_root.append_child(first_root)
        last_root.self_and_descendants.pluck(:name).should == %w(10 0) + expected_order
      end

      it 'should retain sort orders of descendants when moving within the same new parent' do
        path = ('a'..'z').to_a
        z = first_root.find_or_create_by_path(path)
        z_children_names = (100..150).to_a.shuffle.map { |ea| ea.to_s }
        z_children_names.reverse.each { |ea| z.prepend_child(Label.new(name: ea)) }
        z.children(reload = true).pluck(:name).should == z_children_names
        a = first_root.find_by_path(['a'])
        # move b up to a's level:
        b = a.children.first
        a.add_sibling(b)
        b.parent.should == first_root
        z.children(reload = true).pluck(:name).should == z_children_names
      end
    end

    it "shouldn't fail if all children are destroyed" do
      roots = Label.roots.to_a
      roots.each { |ea| ea.children.destroy_all }
      Label.all.to_a.should =~ roots
    end
  end

  context 'descendent destruction' do
    it 'properly destroys descendents created with add_child' do
      a = Label.create(name: 'a')
      b = Label.new(name: 'b')
      a.add_child b
      c = Label.new(name: 'c')
      b.add_child c
      a.destroy
      Label.exists?(id: [a.id, b.id, c.id]).should be_false
    end

    it 'properly destroys descendents created with <<' do
      a = Label.create(name: 'a')
      b = Label.new(name: 'b')
      a.children << b
      c = Label.new(name: 'c')
      b.children << c
      a.destroy
      Label.exists?(id: [a.id, b.id, c.id]).should be_false
    end
  end

  context 'preorder' do
    it 'returns descendants in proper order' do
      create_preorder_tree
      a = Label.root
      a.name.should == 'a'
      expected = ('a'..'r').to_a
      a.self_and_descendants_preordered.collect { |ea| ea.name }.should == expected
      Label.roots_and_descendants_preordered.collect { |ea| ea.name }.should == expected
      # Let's create the second root by hand so we can explicitly set the sort order
      Label.create! do |l|
        l.name = "a1"
        l.order_value = a.order_value + 1
      end
      create_preorder_tree('1')
      # Should be no change:
      a.reload.self_and_descendants_preordered.collect { |ea| ea.name }.should == expected
      expected += ('a'..'r').collect { |ea| "#{ea}1" }
      Label.roots_and_descendants_preordered.collect { |ea| ea.name }.should == expected
    end
  end unless ENV['DB'] == 'sqlite' # sqlite doesn't have a power function.
end
