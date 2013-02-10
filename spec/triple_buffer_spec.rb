#!/usr/bin/env ruby
# encoding: utf-8
# 
# Created by Nat Noordanus on 2013-01-15.
# 
# Copyright (c) 2013 Nat Noordanus. All rights reserved.
# 

require 'rspec'
require './triple_buffer'

class TripleBuffer
  def public_find *args
    find *args
  end
  
  def public_delete_from_index *args
    delete_from_index *args
  end
  
  def public_add_to_index *args
    add_to_index *args
  end
end

describe TripleBuffer, "Indexing" do
  it "Can build an index of a buffer and use it to find any value" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.build_index
    
    buffer.buffer.to_a.flatten.each_with_index do |v,i|
      buffer.public_find(v).include?((i/3).floor).should be_true
    end
  end
  
  it "Can delete and add items to the index" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.build_index

    (0...buffer.size).to_a.shuffle.each do |random_index|
      t = buffer.buffer[random_index*3..random_index*3+2]
      
      buffer.public_find(t[0]).include?(random_index).should be_true
      buffer.public_find(t[1]).include?(random_index).should be_true
      buffer.public_find(t[2]).include?(random_index).should be_true
      
      buffer.public_delete_from_index random_index
      
      buffer.public_find(t[0]).include?(random_index).should be_false
      buffer.public_find(t[1]).include?(random_index).should be_false
      buffer.public_find(t[2]).include?(random_index).should be_false
      
      buffer.public_add_to_index t, random_index
      
      buffer.public_find(t[0]).include?(random_index).should be_true
      buffer.public_find(t[1]).include?(random_index).should be_true
      buffer.public_find(t[2]).include?(random_index).should be_true
    end
  end
  
end


describe TripleBuffer, "CRUD" do
  it "Can loop with triples with index and Can get triples by index, including valid negative indices" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.each_triple_with_index do |t,i|
      
      t0, t1, t2 = buffer.get(i).first
      t0.should eq(t[0])
      t1.should eq(t[1])
      t2.should eq(t[2])
      
      next if i == 0
      t0, t1, t2 = buffer[-i]
      t0.should eq(buffer.buffer[(ntriples-i)*3])
      t1.should eq(buffer.buffer[(ntriples-i)*3+1])
      t2.should eq(buffer.buffer[(ntriples-i)*3+2])
    end
  end
  
  it "Cannot get the value of non-existant triples" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.each_triple_with_index do |t,i|
      
      buffer.get(i+ntriples).first.should eq(nil)
      expect { buffer[i+ntriples] }.to raise_error
      
      buffer.get(-i-ntriples-1).first.should eq(nil)
      expect { buffer[-i-ntriples-1] }.to raise_error      
    end
  end
  
  it "Can update the value of existing triples" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }

    buffer.each_index do |i|
      new_values = 3.times.map { (Random.rand*10**4).to_i.to_f/10**2 }
      buffer.update(i => new_values)
      updated_values = buffer[i]
      (updated_values[0]-new_values[0]).should be < 0.001
      (updated_values[1]-new_values[1]).should be < 0.001
      (updated_values[2]-new_values[2]).should be < 0.001
    end
  end
  
  it "Cannot update the value of non-existant triples" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.each_triple_with_index do |t,i|
      
      buffer.update(i+ntriples => [1.0,2.0,3.0]).first.should be_false
      expect { buffer[i+ntriples] = [1.0,2.0,3.0]}.to raise_error
      
      buffer.update(-i-ntriples-1 => [1.0,2.0,3.0]).first.should be_false
      expect { buffer[-i-ntriples-1] = [1.0,2.0,3.0] }.to raise_error      
    end
  end
  
  it "Can remove existing values" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    
    ntriples.times do
      break unless i = (0...buffer.size-1).to_a.sample
      t1 = buffer[i+1]

      buffer.remove(i)

      t2 = buffer[i]
      t1[0].should eq(t2[0])
      t1[1].should eq(t2[1])
      t1[2].should eq(t2[2])
      
      founda = buffer.public_find(t1[0])
      foundb = buffer.public_find(t1[1])
      foundc = buffer.public_find(t1[2])
      (founda and founda.include?(i)).should be_false
      (foundb and foundb.include?(i)).should be_false
      (foundc and foundc.include?(i)).should be_false
      
    end    
  end
  
  it "Cannat remove non-existant values" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.each_triple_with_index do |t,i|
      buffer.remove(i+ntriples).first.should be_false
      buffer.remove(-i-ntriples-1).first.should be_false
    end
  end
  
  it "Can append new values" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :int, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    removed = buffer.remove((0...buffer.size-1).to_a.sample(4)).count(true)
    
    buffer.append (ntriples).times.map { [(Random.rand*10**6).to_i.to_f/10**4, (Random.rand*10**6).to_i.to_f/10**4, (Random.rand*10**6).to_i.to_f/10**4] }
    buffer.size.should eq(ntriples*2-removed)
    
    buffer.append([[1,2,3]])
    buffer.to_a.last[0].should eq(1)
    buffer.to_a.last[1].should eq(2)
    buffer.to_a.last[2].should eq(3)
    
    n = (0...buffer.size-1).to_a.sample
    buffer.remove n
    buffer.append([[42,52,62]])
    buffer[n][0].should eq(42)
    buffer[n][1].should eq(52)
    buffer[n][2].should eq(62)
  end
  
  it "Updates index to reflect the outcomes of triple updates" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.build_index
    buffer.each_index do |i|
      old_values = buffer[i]
      buffer.update(i => 3.times.map { (Random.rand*10**4).to_i.to_f/10**2 })
      new_values = buffer[i]
      
      buffer.public_find(old_values[0]).include?(i).should be_false
      buffer.public_find(old_values[1]).include?(i).should be_false
      buffer.public_find(old_values[2]).include?(i).should be_false

      buffer.public_find(new_values[0]).include?(i).should be_true
      buffer.public_find(new_values[1]).include?(i).should be_true
      buffer.public_find(new_values[2]).include?(i).should be_true
    end
  end
  
  it "Updates index to reflect the outcomes of removing triples" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.build_index
    
    ntriples.times do
      break unless i = (0...buffer.size-1).to_a.sample
      t = buffer[i]

      buffer.remove(i)
      
      buffer.public_find(t[0]).include?(i).should be_false
      buffer.public_find(t[1]).include?(i).should be_false
      buffer.public_find(t[2]).include?(i).should be_false
    end    
  end
  
  it "Updates index to reflect the outcomes of appending triples" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.build_index
    buffer.append (ntriples).times.map { [(Random.rand*10**6).to_i.to_f/10**4, (Random.rand*10**6).to_i.to_f/10**4, (Random.rand*10**6).to_i.to_f/10**4] }
    
    buffer.to_a.flatten.each_with_index do |v,i|
      buffer.public_find(v).include?((i/3).floor).should be_true
    end
  end
  
  it "Can merge a given other TripleBuffer" do
    ntriples = 8
    buffer1 = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer2 = TripleBuffer.new :type => :float, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    b1 = buffer1.to_a
    b2 = buffer2.to_a
    buffer1.merge! buffer2
    buffer1.to_a.should eq(b1+b2)
  end
  
  it "Doesn't change the content or indexing of a buffer upon optimization" do
    ntriples = 8
    buffer = TripleBuffer.new :type => :int, :array => (ntriples*3).times.map { (Random.rand*10**6).to_i.to_f/10**4 }
    buffer.build_index

    buffer.append (ntriples).times.map { [(Random.rand*10**6).to_i.to_f/10**4, (Random.rand*10**6).to_i.to_f/10**4, (Random.rand*10**6).to_i.to_f/10**4] }
    buffer.remove (0...buffer.size-1).to_a.sample(ntriples)
    buffer.append (ntriples/2).times.map { [(Random.rand*10**6).to_i.to_f/10**4, (Random.rand*10**6).to_i.to_f/10**4, (Random.rand*10**6).to_i.to_f/10**4] }
    
    buffer.to_a.flatten.each_with_index do |v,i|
      buffer.locate(v).include?((i/3).floor).should_not be_false
    end
    
    before = buffer.to_a.flatten
    buffer.optimize
    after = buffer.to_a.flatten
    before.zip(after).map { |b,a| b == a }.all?.should be_true
  end
  
end


describe PointBuffer, "stuff" do
  it "Can access x, y and z components of points" do
    ntriples = 8
    buffer = PointBuffer.new :type => :float, :array => Array.new(ntriples*3) { Random.rand }
    buffer.each_triple_with_index do |t,i|
      buffer.x(i).should eq(t[0])
      buffer.y(i).should eq(t[1])
      buffer.z(i).should eq(t[2])
    end
  end
    
  it "Can perform arithmatic on individual points" do
    ntriples = 8
    buffer = PointBuffer.new :type => :float, :big => true, :array => Array.new(ntriples*3) { Random.rand }
    
    buffer.each_index do |i|
      before = buffer.get(i).first
      addend = Array.new(3) { Random.rand(1000) }
      buffer.add i, addend
      after = buffer.get(i).first
      (before[0] + addend[0]).should eq(after[0])
      (before[1] + addend[1]).should eq(after[1])
      (before[2] + addend[2]).should eq(after[2])
    end
    
    buffer.each_index do |i|
      before = buffer.get(i).first
      sub = Array.new(3) { Random.rand(1000) }
      buffer.sub i, sub
      after = buffer.get(i).first
      (before[0] - sub[0]).should eq(after[0])
      (before[1] - sub[1]).should eq(after[1])
      (before[2] - sub[2]).should eq(after[2])
    end
    
    buffer.each_index do |i|
      before = buffer.get(i).first
      factor = Array.new(3) { Random.rand(1000) }
      buffer.mul i, factor
      after = buffer.get(i).first
      (before[0] * factor[0]).should eq(after[0])
      (before[1] * factor[1]).should eq(after[1])
      (before[2] * factor[2]).should eq(after[2])
    end

    buffer.each_index do |i|
      before = buffer.get(i).first
      div = Array.new(3) { Random.rand(1000) }
      buffer.div i, div
      after = buffer.get(i).first
      (before[0] / div[0]).should eq(after[0])
      (before[1] / div[1]).should eq(after[1])
      (before[2] / div[2]).should eq(after[2])
    end
  end
  
  it "Can perform arithmatic on all points" do
    ntriples = 8
    buffer = PointBuffer.new :type => :float, :big => true, :array => Array.new(ntriples*3) { Random.rand }
    
    d = Array.new(3) { Random.rand(1000) }
    before = buffer.to_a
    buffer.add_all d
    buffer.to_a.zip(before).each do |a,b|
      (b[0] + d[0]).should eq(a[0])
      (b[1] + d[1]).should eq(a[1])
      (b[2] + d[2]).should eq(a[2])
    end

    d = Array.new(3) { Random.rand(1000) }
    before = buffer.to_a
    buffer.sub_all d
    buffer.to_a.zip(before).each do |a,b|
      (b[0] - d[0]).should eq(a[0])
      (b[1] - d[1]).should eq(a[1])
      (b[2] - d[2]).should eq(a[2])
    end

    d = Array.new(3) { Random.rand(1000) }
    before = buffer.to_a
    buffer.mul_all d
    buffer.to_a.zip(before).each do |a,b|
      (b[0] * d[0]).should eq(a[0])
      (b[1] * d[1]).should eq(a[1])
      (b[2] * d[2]).should eq(a[2])
    end

    d = Array.new(3) { Random.rand(1000) }
    before = buffer.to_a
    buffer.div_all d
    buffer.to_a.zip(before).each do |a,b|
      (b[0] / d[0]).should eq(a[0])
      (b[1] / d[1]).should eq(a[1])
      (b[2] / d[2]).should eq(a[2])
    end

    before = buffer.to_a
    buffer.neg_all
    buffer.to_a.zip(before).each do |a,b|
      (-b[0]).should eq(a[0])
      (-b[1]).should eq(a[1])
      (-b[2]).should eq(a[2])
    end
  end
end


describe VertexBuffer, "distance calculations" do
  
  it "Can calculate the distance of a given point from one of its vertices" do
    os = VertexBuffer.new :type => :float, :big => true, :array => [1,2,3,4,5,6,7,8,9,0.2491, 0.8357, 0.4979]
    ts = [[0.1544, 0.1916, 0.7320], [9.706, 0.9580, 7.279], [53.34, 6.687, 3.584], [0.2491, 0.8357, 0.4979]]
    
    # compare with set answers from wolfram alpha
    (os.distance_to(0, ts[0]) - 3.02145).should < 0.00001
    (os.distance_to(1, ts[1]) - 7.10859).should < 0.00001
    (os.distance_to(2, ts[2]) - 46.6739).should < 0.00001
    (os.distance_to(3, ts[3]) - 0).should < 0.00001    
  end
  
  it "Can calculate the distance between two of its vertices" do
    vertices = VertexBuffer.new :type => :float, :big => true, :array => [6.6624, 3.9167, 3.2025, 
                                                                          7.9975, 9.2115, 5.8748, 
                                                                          1.7006, 6.9638, 9.9835, 
                                                                          2.2125, 8.8156, 2.2543]
    
    # compare with set answers from wolfram alpha
    (vertices.distance_between(0, 1) - 6.07936).should < 0.00001
    (vertices.distance_between(1, 2) - 7.84758).should < 0.00001
    (vertices.distance_between(2, 3) - 7.9644).should < 0.00001
    (vertices.distance_between(3, 0) - 6.6858).should < 0.00001    
  end
  
  it "Can calculate the distance between one of its vertices and a given line"
  
  it "Can calculate the distance between one of its vertices and a given line segment"
  
end


describe VectorBuffer, "Vector ops" do
  
  it "Can calculate the length of a specified vector" do
    ntriples = 8
    vectors = VectorBuffer.new :type => :float, :big => false, :array => Array.new(ntriples*3) { Random.rand*100 }
    
    vectors.each_triple_with_index do |t,i|
      vectors.length_of(i).should eq(Math.sqrt( t[0]**2 + t[1]**2 + t[2]**2 ))
    end
  end
  
  it "Can calculate the normal of a specified vector" do
    ntriples = 8
    vectors = VectorBuffer.new :type => :float, :big => false, :array => Array.new(ntriples*3) { Random.rand*100 }
    
    vectors.each_triple_with_index do |t,i|
      l = Math.sqrt( t[0]**2 + t[1]**2 + t[2]**2 )
      n = vectors.normal_of(i)
      n[0].should eq(t[0]/l)
      n[1].should eq(t[1]/l)
      n[2].should eq(t[2]/l)
    end
  end

  it "Can normalize a specified vector in place" do
    ntriples = 8
    vectors = VectorBuffer.new :type => :float, :big => false, :array => Array.new(ntriples*3) { Random.rand*100 }
    
    vectors.each_triple_with_index do |t,i|
      vectors.normalize!(i)
      vectors.normal?(i).should be_true
      (vectors.normal_of(i)[0] - vectors.get(i).first[0]).abs.should < 0.0000001
      (vectors.normal_of(i)[1] - vectors.get(i).first[1]).abs.should < 0.0000001
      (vectors.normal_of(i)[2] - vectors.get(i).first[2]).abs.should < 0.0000001
    end
  end

  it "Can normalize all vectors in place" do
    ntriples = 8
    vectors = VectorBuffer.new :type => :float, :big => false, :array => Array.new(ntriples*3) { Random.rand*100 }
    vectors.normalize_all!
    
    vectors.each_triple_with_index do |t,i|
      vectors.normal?(i).should be_true
      (vectors.normal_of(i)[0] - vectors.get(i).first[0]).abs.should < 0.0000001
      (vectors.normal_of(i)[1] - vectors.get(i).first[1]).abs.should < 0.0000001
      (vectors.normal_of(i)[2] - vectors.get(i).first[2]).abs.should < 0.0000001
    end
  end
  
  it "Can calculate the cross product of a specified vector" do
    vectors = VectorBuffer.new :type => :float, :big => true, :array => [ 6.6624, 3.9167, 3.2025, 
                                                                          7.9975, 9.2115, 5.8748, 
                                                                          1.7006, 6.9638, 9.9835, 
                                                                          2.2125, 8.8156, 2.2543]
    others = [[0.1544, 0.1916, 0.7320], [9.706, 0.9580, 7.279], [53.34, 6.687, 3.584], [2.2125, 8.8156, 2.2543]]
    
    cp = vectors.cross_prod(0, others[0])
    (cp[0] - 2.25343).should  < 0.000001
    (cp[1] - -4.38241).should < 0.000001
    (cp[2] - 0.671777).should < 0.000001
    cp = vectors.cross_prod(1, others[1])
    (cp[0] - 61.4225).should  < 0.000001
    (cp[1] - -1.19299).should < 0.000001
    (cp[2] - 81.7452).should  < 0.000001
    cp = vectors.cross_prod(2, others[2])
    (cp[0] - -41.8014).should < 0.000001
    (cp[1] - 526.425).should < 0.000001
    (cp[2] - -360.077).should < 0.000001
    cp = vectors.cross_prod(3, others[3])
    cp[0].should < 0.000001
    cp[1].should < 0.000001
    cp[2].should < 0.000001
  end

  it "Can calculate the dot product of a specified vector" do
    vectors = VectorBuffer.new :type => :float, :big => true, :array => [ 6.6624, 3.9167, 3.2025, 
                                                                          7.9975, 9.2115, 5.8748, 
                                                                          1.7006, 6.9638, 9.9835, 
                                                                          2.2125, 8.8156, 2.2543]
    others = [[0.1544, 0.1916, 0.7320], [9.706, 0.9580, 7.279], [53.34, 6.687, 3.584], [2.2125, 8.8156, 2.2543]]
    
    (vectors.dot_prod(0, others[0]) - 4.12334428).should < 0.00000001
    (vectors.dot_prod(1, others[1]) - 129.2110212).should < 0.00000001
    (vectors.dot_prod(2, others[2]) - 173.0577986).should < 0.00000001
    (vectors.dot_prod(3, others[3]) - 87.6918281).should < 0.00000001
  end

  it "Can calculate the average normal of a specified set of vectors" do
    ntriples = 8
    vectors = VectorBuffer.new :type => :float, :big => false, :array => Array.new(ntriples*3) { Random.rand*100 }
    
    # this pretty much replicates the target method's code...
    ntriples.times do |i|
      indices = (0...vectors.size).to_a.sample(i+1)
      normal = vectors.avg_normal *indices
      
      average = vectors.get(*indices).transpose.map {|xs| xs.inject(0,:+) / xs.length }
      l = Math.sqrt(average[0]**2 + average[1]**2 + average[2]**2)
      
      normal[0].should eq(average[0]/l)
      normal[1].should eq(average[1]/l)
      normal[2].should eq(average[2]/l)
    end    
  end
  
end